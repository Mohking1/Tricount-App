#!/usr/bin/env python3
import argparse
import base64
import csv
import json
import re
import sys
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any
from urllib import error, request



@dataclass
class Event:
    index: int
    group_name: str
    title: str
    event_type: str
    category_raw: str
    category_name: str
    category_icon: str | None
    total: Decimal
    currency: str
    date_raw: str
    date_iso: str
    date_dt: datetime
    paid_by: str
    rows: list[dict[str, Any]]
    involved: list[dict[str, Any]]


HARDCODED_CATEGORY_ICONS: dict[str, str] = {
    "food": "🍔",
    "groceries": "🛒",
    "transport": "🚌",
    "accommodation": "🏠",
    "accomodation": "🏠",
    "entertainment": "🎬",
    "shopping": "🛍️",
    "restaurants": "🍝",
    "restaurant": "🍝",
    "rent": "🏡",
    "transfer": "💸",
    "transfered": "💸",
    "furniture": "🛋️",
    "cleaning & hygiene": "🧹",
    "water": "💧",
    "other": "🧾",
}


def hardcoded_category_icon(name: str | None) -> str:
    key = (name or "").strip().lower()
    return HARDCODED_CATEGORY_ICONS.get(key, "🧾")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import tricount CSV into Supabase with BALANCE settlement logic."
    )
    parser.add_argument("--csv", required=True, help="Path to tricount CSV export")
    parser.add_argument(
        "--name",
        default=None,
        help="Name for created tricount (default: '<group> Imported <today>')",
    )
    parser.add_argument(
        "--supabase-url",
        default="https://yiyhlredrtamviyhusco.supabase.co",
        help="Supabase project URL",
    )
    parser.add_argument(
        "--anon-key",
        default=None,
        help="Supabase anon key (default: read from lib/main.dart)",
    )
    parser.add_argument(
        "--access-token",
        default=None,
        help="Supabase user access token (or set SUPABASE_ACCESS_TOKEN env var)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Do everything except writing to Supabase",
    )
    return parser.parse_args()


def to_decimal(value: str) -> Decimal:
    try:
        return Decimal(str(value).strip())
    except (InvalidOperation, ValueError) as exc:
        raise ValueError(f"Invalid numeric value: {value!r}") from exc


def parse_date_to_iso(raw: str) -> tuple[str, datetime]:
    s = (raw or "").strip()
    if not s:
        dt = datetime.now(timezone.utc)
        return dt.isoformat(), dt

    for fmt in ("%Y-%m-%d", "%Y-%m-%d %H:%M:%S"):
        try:
            dt = datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
            if fmt == "%Y-%m-%d":
                dt = dt.replace(hour=12, minute=0, second=0)
            return dt.isoformat(), dt
        except ValueError:
            pass

    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.isoformat(), dt
    except ValueError:
        dt = datetime.now(timezone.utc)
        return dt.isoformat(), dt


def parse_custom_category(category_raw: str) -> tuple[str, str | None, bool]:
    raw = (category_raw or "").strip()
    if not raw:
        return "Other", None, False

    # Normalize common categories
    normalized = raw.capitalize()
    if normalized == "Accomodation" or normalized == "Accommodation":
        normalized = "Accommodation"
    elif normalized == "Groceries" or normalized == "Food" or normalized == "Restaurants" or normalized == "Rent" or normalized == "Transport":
        pass
    else:
        pass # allow normal formatting

    payload = None
    is_custom = False

    if raw.startswith("CUSTOM:"):
        payload = raw[len("CUSTOM:") :].strip()
        is_custom = True
    elif raw.startswith("CUSTOM(") and raw.endswith(")"):
        payload = raw[len("CUSTOM(") : -1].strip()
        is_custom = True
    elif raw.startswith("{") and raw.endswith("}"):
        payload = raw
        is_custom = True

    if payload:
        try:
            obj = json.loads(payload)
            name = str(
                obj.get("name")
                or obj.get("label")
                or obj.get("t")
                or "Custom"
            ).strip() or "Custom"
            icon = obj.get("icon") or obj.get("i")
            return name, str(icon) if icon else None, is_custom
        except json.JSONDecodeError:
            pass

    return normalized, None, is_custom


def extract_embedded_icon(name: str) -> tuple[str, str | None]:
    s = (name or "").strip()
    if not s:
        return "Other", None
    parts = s.split()
    if len(parts) >= 2:
        last = parts[-1]
        if any(ord(ch) > 127 for ch in last):
            return " ".join(parts[:-1]).strip() or s, last
    return s, None


def event_key(row: dict[str, str]) -> tuple[str, ...]:
    return (
        (row.get("group_name") or "").strip(),
        (row.get("expense_title") or "").strip(),
        (row.get("type") or "").strip().upper(),
        (row.get("category") or "").strip(),
        (row.get("total_amount") or "").strip(),
        (row.get("currency") or "").strip(),
        (row.get("date") or "").strip(),
        (row.get("paid_by") or "").strip(),
    )


def extract_anon_key() -> str:
    main = Path("lib/main.dart")
    if not main.exists():
        raise RuntimeError("Could not find lib/main.dart to read anonKey")
    text = main.read_text(encoding="utf-8")
    match = re.search(r"anonKey:\s*'([^']+)'", text)
    if not match:
        raise RuntimeError("Could not parse anonKey from lib/main.dart")
    return match.group(1)


def decode_jwt_sub(access_token: str) -> str | None:
    try:
        payload_b64 = access_token.split(".")[1]
        pad = "=" * (-len(payload_b64) % 4)
        payload = json.loads(base64.urlsafe_b64decode(payload_b64 + pad))
        sub = payload.get("sub")
        if not sub:
            return None
        return str(sub)
    except Exception as exc:
        raise RuntimeError("Failed to decode JWT payload") from exc


def supabase_request(
    url: str,
    anon_key: str,
    access_token: str,
    method: str,
    path: str,
    payload: Any | None = None,
    prefer: str | None = None,
) -> Any:
    body = None
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")

    req = request.Request(url=f"{url}/rest/v1/{path}", data=body, method=method)
    req.add_header("apikey", anon_key)
    req.add_header("Authorization", f"Bearer {access_token}")
    req.add_header("Content-Type", "application/json")
    if prefer:
        req.add_header("Prefer", prefer)

    try:
        with request.urlopen(req) as resp:
            raw = resp.read().decode("utf-8")
            if not raw:
                return None
            return json.loads(raw)
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"Supabase {method} {path} failed: {exc.code} {detail}") from exc


def build_events(rows: list[dict[str, str]]) -> list[Event]:
    events: list[Event] = []
    current_rows: list[dict[str, str]] = []
    current_key: tuple[str, ...] | None = None

    for row in rows:
        k = event_key(row)
        if current_key is None or k == current_key:
            current_rows.append(row)
            current_key = k
        else:
            events.append(_make_event(len(events), current_key, current_rows))
            current_rows = [row]
            current_key = k

    if current_rows and current_key is not None:
        events.append(_make_event(len(events), current_key, current_rows))

    return events


def _make_event(index: int, key: tuple[str, ...], rows: list[dict[str, str]]) -> Event:
    group_name, title, event_type, cat_raw, total_raw, currency, date_raw, paid_by = key
    total = to_decimal(total_raw)
    cat_name, cat_icon, _ = parse_custom_category(cat_raw)
    date_iso, date_dt = parse_date_to_iso(date_raw)
    return Event(
        index=index,
        group_name=group_name,
        title=title,
        event_type=event_type,
        category_raw=cat_raw,
        category_name=cat_name,
        category_icon=cat_icon,
        total=total,
        currency=currency,
        date_raw=date_raw,
        date_iso=date_iso,
        date_dt=date_dt,
        paid_by=paid_by,
        rows=rows,
        involved=[],
    )



def init_normal_involved(events: list[Event]) -> None:
    for event in events:
        if event.event_type != "NORMAL":
            continue
        involved = []
        for row in event.rows:
            owes_who = (row.get("owes_who") or "").strip()
            amount = to_decimal(row.get("owes_amount") or "0")
            if not owes_who:
                continue
            involved.append(
                {
                    "name": owes_who,
                    "amount": amount,
                    "paid_amount": Decimal("0"),
                }
            )
        event.involved = involved


def build_participants(events: list[Event]) -> tuple[dict[str, str], list[dict[str, Any]]]:
    names = set()
    for e in events:
        if e.paid_by:
            names.add(e.paid_by)
        for row in e.rows:
            n = (row.get("owes_who") or "").strip()
            if n:
                names.add(n)

    name_to_id = {
        name: str(uuid.uuid5(uuid.NAMESPACE_DNS, f"ghost:{name}"))
        for name in sorted(names)
    }

    participants = []
    for name, pid in name_to_id.items():
        participants.append({
            "id": pid,
            "name": name,
            "is_ghost": True,
        })
    return name_to_id, participants


def build_expense_rows(events: list[Event], name_to_id: dict[str, str]) -> list[dict[str, Any]]:
    expense_rows: list[dict[str, Any]] = []
    for e in events:
        if e.event_type != "NORMAL":
            continue

        involved = []
        for line in e.involved:
            user_id = name_to_id.get(line["name"])
            if not user_id:
                continue
            entry = {
                "user_id": user_id,
                "amount": float(line["amount"]),
            }
            paid = line["paid_amount"]
            # Never set paid_amount for payer's own share; it causes UI and balance glitches.
            if paid > 0 and line["name"] != e.paid_by:
                entry["paid_amount"] = float(paid)
            involved.append(entry)

        expense_rows.append(
            {
                "name": e.title,
                "paid_by": e.paid_by,
                "user_id": name_to_id.get(e.paid_by),
                "value": float(e.total),
                "category": e.category_name,
                "created_at": e.date_iso,
                "involved_participants": involved,
                "type": "expense",
                "payment_method": "Online",
            }
        )
    return expense_rows


def build_custom_categories(events: list[Event]) -> list[dict[str, str | None]]:
    categories: dict[str, dict[str, str | None]] = {}
    for e in events:
        parsed_name, _, _ = parse_custom_category(e.category_raw)
        if e.event_type == "BALANCE":
            continue
        name, embedded_icon = extract_embedded_icon(parsed_name)
        icon = e.category_icon or embedded_icon or hardcoded_category_icon(name)
        if name not in categories:
            categories[name] = {
                "name": name,
                "icon": icon,
                "color": None,
            }
    return list(categories.values())


def insert_batches(
    supabase_url: str,
    anon_key: str,
    access_token: str,
    table: str,
    rows: list[dict[str, Any]],
    batch_size: int = 100,
) -> None:
    for i in range(0, len(rows), batch_size):
        batch = rows[i : i + batch_size]
        supabase_request(
            url=supabase_url,
            anon_key=anon_key,
            access_token=access_token,
            method="POST",
            path=table,
            payload=batch,
            prefer="return=minimal",
        )


def main() -> int:
    args = parse_args()
    csv_path = Path(args.csv)
    if not csv_path.exists():
        print(f"ERROR: CSV not found: {csv_path}")
        return 1

    anon_key = args.anon_key or extract_anon_key()
    access_token = args.access_token or __import__("os").environ.get("SUPABASE_ACCESS_TOKEN")
    if not access_token and not args.dry_run:
        print("ERROR: Missing access token. Pass --access-token or set SUPABASE_ACCESS_TOKEN.")
        return 1

    with csv_path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    if not rows:
        print("ERROR: CSV is empty")
        return 1

    expected = {
        "group_name",
        "expense_title",
        "type",
        "category",
        "total_amount",
        "currency",
        "date",
        "paid_by",
        "owes_who",
        "owes_amount",
    }
    missing = sorted(expected - set(rows[0].keys()))
    if missing:
        print(f"ERROR: Missing columns: {', '.join(missing)}")
        return 1

    events = build_events(rows)
    init_normal_involved(events)
    name_to_id, participants = build_participants(events)
    expense_rows = build_expense_rows(events, name_to_id)
    custom_categories = build_custom_categories(events)

    user_id = decode_jwt_sub(access_token) if access_token else None
    group_name = events[0].group_name or "Imported Group"
    tricount_name = args.name or f"{group_name} Imported {datetime.now().date().isoformat()}"

    tricount_payload = {
        "name": tricount_name,
        "description": "Imported from CSV (expenses only; transfers handled manually).",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "participants": participants,
        "participant_ids": [p["id"] for p in participants],
        "emoji": "📥",
    }
    if user_id:
        tricount_payload["created_by"] = user_id

    print("SUMMARY")
    print(f"  source_rows: {len(rows)}")
    print(f"  events: {len(events)}")
    print(f"  normal_events_imported: {len(expense_rows)}")
    print(f"  balance_events_processed: {sum(1 for e in events if e.event_type == 'BALANCE')}")
    print(f"  custom_categories: {len(custom_categories)}")
    ghost_count = sum(1 for p in participants if p.get("is_ghost"))
    print(f"  participants(total): {len(participants)}")
    print(f"  participants(ghost): {ghost_count}")

    if args.dry_run:
        print("DRY_RUN=1 No data written.")
        return 0

    created = supabase_request(
        url=args.supabase_url,
        anon_key=anon_key,
        access_token=access_token,
        method="POST",
        path="tricounts",
        payload=tricount_payload,
        prefer="return=representation",
    )
    if not created or not isinstance(created, list):
        print("ERROR: Tricount creation returned unexpected payload")
        return 1
    tricount = created[0]
    tricount_id = tricount["id"]

    if custom_categories:
        category_rows = []
        for c in custom_categories:
            category_rows.append(
                {
                    "tricount_id": tricount_id,
                    "name": c["name"],
                    "icon": c.get("icon"),
                    "color": c.get("color"),
                }
            )
        insert_batches(args.supabase_url, anon_key, access_token, "categories", category_rows)

    for row in expense_rows:
        row["tricount_id"] = tricount_id
    insert_batches(args.supabase_url, anon_key, access_token, "expenses", expense_rows)

    print("IMPORT_OK=1")
    print(f"TRICOUNT_ID={tricount_id}")
    print(f"JOIN_CODE={tricount_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())