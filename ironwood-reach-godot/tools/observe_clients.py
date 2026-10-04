#!/usr/bin/env python3
"""Read redacted passive browser logs; never connect or issue game commands."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def latest(client):
    path = ROOT / '.runtime/logs' / f'browser-client-{client}.jsonl'
    with path.open('rb') as stream:
        offset = max(0, path.stat().st_size - 1048576)
        stream.seek(offset)
        lines = stream.read().splitlines()
    if offset:
        lines = lines[1:]
    for line in reversed(lines):
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get('kind') == 'websocket_received' and event.get('data', {}).get('type') == 'snapshot':
            return event
    raise RuntimeError(f'No complete recent snapshot for client {client}.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--save', type=Path)
    args = parser.parse_args()
    events = {str(client): latest(client) for client in (1, 2)}
    if args.save:
        output = args.save.resolve()
        if not output.is_relative_to(ROOT / 'docs/evidence'):
            parser.error('Saved observations must stay inside this project evidence folder.')
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open('x') as stream:
            json.dump({'observed_at_utc': datetime.now(timezone.utc).isoformat(),
                       'scope': 'Passive redacted browser snapshots, supplementary to real XTEST play.',
                       'clients': events}, stream, indent=2)
            stream.write('\n')
    for client, event in events.items():
        state = event['data']
        summary = {key: state.get(key) for key in ['build_id', 'tick', 'revision', 'status', 'gold', 'spent', 'gathered', 'reserved_gold', 'reservations', 'abilities', 'connections', 'result']}
        summary['units'] = [{key: unit.get(key) for key in ['id', 'team', 'hp', 'x', 'z', 'order', 'goal', 'state', 'march_ticks', 'shield_ticks']} for unit in state.get('units', [])]
        summary['buildings'] = [{key: building.get(key) for key in ['id', 'hp', 'ready', 'build_ticks', 'overcharge_ticks', 'shutdown_ticks']} for building in state.get('buildings', [])]
        print(json.dumps({'client': client, 'snapshot_at': event['at'], **summary}))


if __name__ == '__main__':
    main()
