"""Génère les seeds : 15 jours de commandes (graine fixe), plus quatre défauts injectés.

- 3 défauts dans le dernier jour : client inconnu (999), montant négatif (-5), chute de volume (45 commandes)
- 1 défaut dans le premier jour : un doublon
Les chargements du dernier jour sont horodatés 6 h avant l'exécution (retard modéré).
"""
import argparse
import datetime as dt
import random

parser = argparse.ArgumentParser()
parser.add_argument("--clean", action="store_true", help="données saines : aucun défaut injecté (base des mutations)")
clean = parser.parse_args().clean

random.seed(7)
# Tout est généré en UTC : BigQuery lit un horodatage sans fuseau comme de l'UTC.
now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0, tzinfo=None)
rows, oid = [], 1
for d in range(14, -1, -1):
    day = (now - dt.timedelta(days=d)).date()
    n = 45 if (d == 0 and not clean) else random.randint(92, 108)
    for _ in range(n):
        if d == 0:   # aujourd'hui : jamais dans le futur, quelle que soit l'heure d'exécution
            span = max(1, int((now - dt.datetime.combine(day, dt.time())).total_seconds()) - 3600)
            ts = dt.datetime.combine(day, dt.time()) + dt.timedelta(seconds=random.randint(0, span))
        else:
            ts = dt.datetime.combine(day, dt.time(random.randint(0, 11), random.randint(0, 59)))
        loaded = now - dt.timedelta(hours=6) if d == 0 else ts + dt.timedelta(hours=1)
        rows.append((oid, random.randint(1, 40), round(random.uniform(8, 120), 2), ts, loaded))
        oid += 1
late = now - dt.timedelta(hours=6)
if not clean:
    rows.append(rows[0])                                                         # doublon (premier jour)
    rows.append((oid, 999, 20.0, now, late)); oid += 1                            # client inconnu
    rows.append((oid, 3, -5.0, now, late))                                        # montant négatif

fmt = lambda t: t.isoformat(sep=" ")
with open("seeds/raw_orders.csv", "w") as f:
    f.write("order_id,customer_id,amount,ordered_at,_etl_loaded_at\n")
    for r in rows:
        f.write(f"{r[0]},{r[1]},{r[2]},{fmt(r[3])},{fmt(r[4])}\n")
with open("seeds/raw_customers.csv", "w") as f:
    f.write("customer_id,email,country\n")
    for i in range(1, 41):
        f.write(f"{i},c{i}@ex.com,{random.choice(['FR', 'FR', 'FR', 'DE', 'ES'])}\n")
print(f"{len(rows)} commandes générées ({'saines' if clean else 'avec défauts'}), ancrées sur {now}")
