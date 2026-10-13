#!/usr/bin/env python3
"""Render native Grafana provisioning files."""
import json
import os
from pathlib import Path
import tempfile

root = Path(os.environ.get('PM_COMPOSE_PROJECT_DIRECTORY') or os.environ['SCRIPT_DIR'])
source = root / 'observability/grafana/alerting'
target = root / '.portmason/observability-alerting'
target.mkdir(parents=True, exist_ok=True)
enabled = os.environ.get('OBSERVABILITY_NOTIFICATION_ENABLED', 'false').lower() in ('true', '1', 'yes', 'on')
variables = {key: os.environ.get(key, '') for key in ('STACK', 'DEPLOY_ENV', 'OBSERVABILITY_NOTIFICATION_DELIVERY_ADDRESS')}
if not variables['STACK'] or not variables['DEPLOY_ENV']:
    raise SystemExit('Alerting requires stack and environment identity')

def expand(value):
    if isinstance(value, str):
        for key, replacement in variables.items():
            value = value.replace('${' + key + '}', replacement)
        return value
    if isinstance(value, list): return [expand(v) for v in value]
    if isinstance(value, dict): return {k: expand(v) for k, v in value.items()}
    return value

def write_atomic(path, content, mode):
    fd, temp = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as handle: handle.write(content)
        os.chmod(temp, mode)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp): os.unlink(temp)

for name in ('rules.json', 'notifications.json'):
    data = expand(json.loads((source / name).read_text()))
    for group in data.get('groups', []):
        for rule in group['rules']:
            rule['isPaused'] = not enabled or rule.get('isPaused', False)
    if name == 'notifications.json' and not variables['OBSERVABILITY_NOTIFICATION_DELIVERY_ADDRESS']:
        if enabled: raise SystemExit('Notification address required')
        data = {'apiVersion': 1}
    write_atomic(target / name, json.dumps(data, indent=2) + '\n', 0o644)

print('Rendered Grafana alerting; notifications ' + ('enabled' if enabled else 'disabled'))
