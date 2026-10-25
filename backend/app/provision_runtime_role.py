"""Run only in the one-shot migration container with administrator credentials."""

import os
import re

import psycopg
from psycopg import sql

from app.config import get_settings


def main() -> None:
    settings = get_settings()
    username = os.environ.get("APP_DB_USER", "")
    password = os.environ.get("APP_DB_PASSWORD", "")
    if (re.fullmatch(r"[a-z][a-z0-9_]{0,62}", username) is None
            or username == settings.postgres_user or len(password) < 32):
        raise SystemExit("Set a separate APP_DB_USER and an APP_DB_PASSWORD of at least 32 characters")
    role = sql.Identifier(username)
    try:
        with psycopg.connect(
            host=settings.postgres_host, port=settings.postgres_port, dbname=settings.postgres_db,
            user=settings.postgres_user, password=settings.postgres_password.get_secret_value(),
            connect_timeout=settings.db_connect_timeout,
        ) as db:
            exists = db.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (username,)).fetchone()
            if not exists:
                db.execute(sql.SQL("CREATE ROLE {} LOGIN").format(role))
            owns_objects = db.execute(
                "SELECT 1 FROM pg_class c JOIN pg_roles r ON r.oid = c.relowner WHERE r.rolname = %s LIMIT 1",
                (username,),
            ).fetchone()
            if owns_objects:
                raise ValueError("Runtime role must not own database objects")
            db.execute(sql.SQL(
                "ALTER ROLE {} WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT "
                "NOREPLICATION NOBYPASSRLS PASSWORD {}"
            ).format(role, sql.Literal(password)))
            memberships = db.execute(
                "SELECT parent.rolname FROM pg_auth_members m "
                "JOIN pg_roles parent ON parent.oid=m.roleid JOIN pg_roles child ON child.oid=m.member "
                "WHERE child.rolname=%s", (username,),
            ).fetchall()
            for (parent,) in memberships:
                db.execute(sql.SQL("REVOKE {} FROM {}").format(sql.Identifier(parent), role))
            db.execute(sql.SQL("REVOKE ALL ON DATABASE {} FROM {}").format(
                sql.Identifier(settings.postgres_db), role,
            ))
            db.execute(sql.SQL("GRANT CONNECT ON DATABASE {} TO {}").format(
                sql.Identifier(settings.postgres_db), role,
            ))
            db.execute("REVOKE CREATE ON SCHEMA public FROM PUBLIC")
            db.execute(sql.SQL("REVOKE ALL ON SCHEMA public FROM {}").format(role))
            db.execute(sql.SQL("GRANT USAGE ON SCHEMA public TO {}").format(role))
            db.execute(sql.SQL("REVOKE ALL ON ALL TABLES IN SCHEMA public FROM {}").format(role))
            db.execute(sql.SQL("REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM {}").format(role))
            db.execute(sql.SQL(
                "GRANT SELECT ON public.restrooms, public.stalls, public.sensors, "
                "public.sensor_events, public.restroom_snapshots TO {}"
            ).format(role))
            db.execute(sql.SQL("GRANT UPDATE (occupied, updated_at) ON public.stalls TO {}").format(role))
            db.execute(sql.SQL("GRANT UPDATE (last_sequence, last_occupied) ON public.sensors TO {}").format(role))
            db.execute(sql.SQL("GRANT INSERT, DELETE ON public.sensor_events TO {}").format(role))
            db.execute(sql.SQL("GRANT USAGE ON SEQUENCE public.sensor_events_id_seq TO {}").format(role))
    except (psycopg.Error, ValueError):
        # DDL may contain a password; do not expose the driver exception/SQL.
        raise SystemExit("Runtime DB role provisioning failed; check administrator access and role ownership") from None
    print("Restricted runtime database role configured")


if __name__ == "__main__":
    main()
