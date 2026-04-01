#!/usr/bin/env python3
import argparse
import json
import urllib.parse
import urllib.request
from datetime import datetime, timezone


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Rebuild personal tracker rows from tricount cash-flow logic"
    )
    p.add_argument("--base-url", required=True)
    p.add_argument("--api-key", required=True)
    p.add_argument("--user-id", required=True)
    return p.parse_args()


def main() -> int:
    args = parse_args()
    base = args.base_url.rstrip("/") + "/rest/v1"
    key = args.api_key
    uid = args.user_id

    def req(path: str, method: str = "GET", payload=None):
        data = None if payload is None else json.dumps(payload).encode("utf-8")
        r = urllib.request.Request(f"{base}/{path}", data=data, method=method)
        r.add_header("apikey", key)
        r.add_header("Authorization", f"Bearer {key}")
        r.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(r) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else None

    tricounts = req(f"tricounts?select=id&participant_ids=cs.{{{uid}}}") or []
    tricount_ids = [t["id"] for t in tricounts]

    rows = req(f"personal_transactions?user_id=eq.{uid}&select=id,type,notes") or []

    def should_delete(row) -> bool:
        tx_type = (row.get("type") or "").lower()
        notes = (row.get("notes") or "").lower()
        return (tx_type == "expense") or (
            tx_type == "income"
            and any(k in notes for k in ["group", "transfer", "settlement"])
        )

    delete_ids = [r["id"] for r in rows if should_delete(r)]
    for txid in delete_ids:
        req(f"personal_transactions?id=eq.{urllib.parse.quote(txid)}", method="DELETE")

    rebuilt = []
    if tricount_ids:
        id_filter = ",".join(tricount_ids)
        expenses = req(
            "expenses?select=name,type,value,category,created_at,user_id,payment_method,involved_participants"
            f"&tricount_id=in.({id_filter})&order=created_at.asc"
        ) or []

        for e in expenses:
            etype = (e.get("type") or "expense").lower()
            payer = str(e.get("user_id") or "")
            amount = float(e.get("value") or 0)
            if amount <= 0:
                continue
            mode = (e.get("payment_method") or "online").lower()
            date = e.get("created_at") or datetime.now(timezone.utc).isoformat()

            if etype == "expense" and payer == uid:
                rebuilt.append(
                    {
                        "user_id": uid,
                        "name": e.get("name") or "Group expense",
                        "amount": amount,
                        "type": "expense",
                        "payment_mode": mode,
                        "category": e.get("category") or "Other",
                        "date": date,
                        "notes": "Group expense payment (full bill paid by you)",
                    }
                )
            elif etype == "income" and payer == uid:
                rebuilt.append(
                    {
                        "user_id": uid,
                        "name": e.get("name") or "Group income",
                        "amount": amount,
                        "type": "income",
                        "payment_mode": mode,
                        "category": e.get("category") or "Other",
                        "date": date,
                        "notes": "Group income received",
                    }
                )
            elif etype == "transfer":
                receiver = ""
                involved = e.get("involved_participants")
                if isinstance(involved, list) and involved and isinstance(involved[0], dict):
                    receiver = str(involved[0].get("user_id") or involved[0].get("id") or "")

                if payer == uid:
                    rebuilt.append(
                        {
                            "user_id": uid,
                            "name": e.get("name") or "Transfer",
                            "amount": amount,
                            "type": "expense",
                            "payment_mode": mode,
                            "category": "Transfer",
                            "date": date,
                            "notes": "Transfer sent for group settlement",
                        }
                    )
                elif receiver == uid:
                    rebuilt.append(
                        {
                            "user_id": uid,
                            "name": e.get("name") or "Transfer",
                            "amount": amount,
                            "type": "income",
                            "payment_mode": mode,
                            "category": "Transfer",
                            "date": date,
                            "notes": "Transfer received for group settlement",
                        }
                    )

    for i in range(0, len(rebuilt), 200):
        req("personal_transactions", method="POST", payload=rebuilt[i : i + 200])

    final_rows = req(f"personal_transactions?user_id=eq.{uid}&select=id") or []
    print(f"tricounts_found={len(tricount_ids)}")
    print(f"deleted_rows={len(delete_ids)}")
    print(f"rebuilt_rows={len(rebuilt)}")
    print(f"final_personal_rows={len(final_rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
