"""PC controls for temporary display states; no sensor secrets or DB writes."""
import argparse
import json
from pathlib import Path
import random
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

from app.config import get_settings
from app.schemas.simulation import SimulationUpdate


class SimulationError(Exception):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Never forward the control credential to a redirected host.


class Client:
    def __init__(self, url):
        parts = urlsplit(url)
        if (parts.scheme not in {"http", "https"} or not parts.hostname or parts.username
                or parts.password or parts.query or parts.fragment
                or (parts.scheme == "http" and parts.hostname not in {"localhost", "127.0.0.1", "::1"})):
            raise SimulationError("주소는 localhost HTTP 또는 HTTPS여야 합니다.")
        self.url = url.rstrip("/")
        self.opener = build_opener(ProxyHandler({}), NoRedirect())

    def request(self, path, payload=None):
        headers = {"Accept": "application/json"}
        data = None
        if payload is not None:
            key = get_settings().simulation_api_key.get_secret_value()
            if not key:
                raise SimulationError("backend/.env에 SIMULATION_API_KEY를 설정해 주세요.")
            headers.update({"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
            data = json.dumps(payload, allow_nan=False).encode()
        try:
            with self.opener.open(Request(self.url + path, data=data, headers=headers), timeout=10) as response:
                return json.load(response)
        except HTTPError as error:
            messages = {
                401: "시뮬레이션 키가 서버 설정과 일치하지 않습니다.",
                404: "시뮬레이션이 꺼져 있거나 해당 화장실/칸이 없습니다. ENABLE_SIMULATION 설정을 확인하세요.",
                422: "요청한 칸과 상태를 확인하세요. 최대 64칸까지 지정할 수 있습니다.",
                503: "서버 DB 연결과 시뮬레이션 키 설정을 확인하세요.",
            }
            raise SimulationError(messages.get(error.code, f"서버 요청 실패 (HTTP {error.code})")) from None
        except (URLError, TimeoutError, ValueError):
            raise SimulationError("서버에 연결하거나 응답을 읽지 못했습니다. Docker와 API 주소를 확인하세요.") from None

    def rooms(self, restroom_id=None):
        rooms = self.request("/api/restrooms")
        if restroom_id is not None:
            rooms = [room for room in rooms if room["id"] == restroom_id]
        if not rooms:
            raise SimulationError("대상 화장실이 없습니다. 먼저 시설 seed와 list를 확인하세요.")
        return [self.request(f"/api/restrooms/{room['id']}") for room in rooms]


def random_states(rooms, rate, seed=None):
    generator = random.Random(seed)
    return [{"stall_id": stall["id"], "occupied": generator.random() < rate}
            for room in rooms for stall in room["stalls"]]


def parse_pattern(pattern, stalls):
    tokens = pattern.replace(" ", "").split(",")
    if len(tokens) != len(stalls) or any(token not in {"0", "1", "?"} for token in tokens):
        raise SimulationError(f"칸 번호 순서대로 {len(stalls)}개를 지정하세요. 예: 0,1,?,0 (0=빈칸, 1=사용 중, ?=미확인)")
    return [{"stall_id": stall["id"], "occupied": {"0": False, "1": True, "?": None}[token]}
            for stall, token in zip(sorted(stalls, key=lambda s: s["stall_number"]), tokens)]


def parser():
    root = argparse.ArgumentParser(description="화장실 PC 테스트 상태 관리 (실제 DB는 변경하지 않음)")
    root.add_argument("--url", default="http://127.0.0.1:8000")
    commands = root.add_subparsers(dest="command", required=True)
    for name in ("list", "random", "reset"):
        command = commands.add_parser(name)
        command.add_argument("--restroom", type=int, help="list에 표시되는 화장실 ID. 생략하면 전체")
        if name == "random":
            command.add_argument("--occupied-rate", type=float, default=0.5, help="사용 중 비율 0~1, 기본 0.5")
            command.add_argument("--seed", type=int, help="같은 난수 결과를 재현할 번호")
    command = commands.add_parser("set")
    command.add_argument("--restroom", type=int, required=True)
    choice = command.add_mutually_exclusive_group(required=True)
    choice.add_argument("--stall", type=int, help="화장실 내부 칸 번호")
    choice.add_argument("--pattern", help="칸 번호 순서로 0,1,?,0")
    command.add_argument("--state", choices=("free", "occupied", "unknown"))
    for name in ("export", "apply"):
        command = commands.add_parser(name)
        command.add_argument("file", type=Path)
    return root


def run(args):
    client = Client(args.url)
    if args.command == "apply":
        payload = SimulationUpdate.model_validate(json.loads(args.file.read_text())).model_dump()
        result = client.request("/api/simulation/stalls", payload)
    elif args.command == "reset" and args.restroom is None:
        result = client.request("/api/simulation/reset", {"stall_ids": None})
    else:
        rooms = client.rooms(getattr(args, "restroom", None))
        if args.command == "list":
            print("0=빈칸 / 1=사용 중 / ?=미확인 / *=테스트 상태")
            for room in rooms:
                values = [f"{s['stall_number']}:{'?' if s['occupied'] is None else int(s['occupied'])}"
                          f"{'*' if s.get('is_simulated') else ''}(ID {s['id']})" for s in room["stalls"]]
                print(f"화장실 ID {room['id']} | {room['name']} | " + " ".join(values))
            return
        if args.command == "reset":
            result = client.request("/api/simulation/reset", {"stall_ids": [s["id"] for r in rooms for s in r["stalls"]]})
        else:
            if args.command == "random":
                if not 0 <= args.occupied_rate <= 1:
                    raise SimulationError("occupied-rate는 0~1이어야 합니다.")
                states = random_states(rooms, args.occupied_rate, args.seed)
            elif args.command == "set":
                if args.pattern is not None:
                    if args.state is not None:
                        raise SimulationError("pattern과 state는 함께 지정하지 않습니다.")
                    states = parse_pattern(args.pattern, rooms[0]["stalls"])
                else:
                    stalls = [s for s in rooms[0]["stalls"] if s["stall_number"] == args.stall]
                    if not stalls or args.state is None:
                        raise SimulationError("유효한 칸 번호와 --state free/occupied/unknown을 지정하세요.")
                    states = [{"stall_id": stalls[0]["id"], "occupied": {"free": False, "occupied": True, "unknown": None}[args.state]}]
            else:  # export
                states = [{"stall_id": s["id"], "occupied": s["occupied"]} for r in rooms for s in r["stalls"]]
                with args.file.open("x", encoding="utf-8") as output:
                    json.dump({"states": states}, output, ensure_ascii=False, indent=2)
                    output.write("\n")
                print(f"{len(states)}칸 저장: {args.file}. occupied를 true/false/null로 편집한 뒤 apply로 적용하세요.")
                return
            payload = SimulationUpdate(states=states).model_dump()
            result = client.request("/api/simulation/stalls", payload)
    print(f"{result['changed']}칸 반영 완료. 앱의 목록·약도·추천에 자동 반영됩니다.")
    if args.command != "reset":
        print("테스트 상태입니다. reset 또는 서버 재시작 시 실제 센서 상태로 돌아갑니다.")


def main():
    try:
        run(parser().parse_args())
        return 0
    except SimulationError as error:
        print(str(error), file=sys.stderr)
    except (OSError, ValueError):
        print("파일·입력·환경변수 형식을 확인하세요. export는 기존 파일을 덮어쓰지 않습니다.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
