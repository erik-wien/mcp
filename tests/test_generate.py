"""Tests for generate.py — run with: pytest tests/ -v"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

import copy
import pytest
from generate import resolve_app_config, resolve_db, sanitize, generate_update_md

# ── Fixture config ─────────────────────────────────────────────────────────────

FIXTURE = {
    'shared': {
        'smtp': {
            'host': 'smtp.example.com',
            'port': 587,
            'user': 'smtp_user',
            'password': 'smtp_pass',
        },
        'slack': {
            'bot_token': 'xoxb-test-token',
        },
        'auth_db': {
            'host': 'localhost',
            'name': 'shared_auth',
            'user': 'auth_user',
            'password': 'auth_pass',
        },
        'targets': {
            'local': {'web_root': '/var/www'},
            'akadbrain': {'ssh_host': 'akadbrain.local', 'ssh_user': 'erik', 'ssh_key': '~/.ssh/id_rsa'},
            'world4you': {'ftp_host': 'ftp.example.com', 'ftp_user': 'ftpu', 'ftp_password': 'ftpp'},
        },
    },
    'apps': {
        'flatdb': {
            'legacy_config': 'config.ini',
            'targets': ['local', 'akadbrain'],
            'deploy': {
                'local': {'dest': '/var/www/flatdb'},
                'akadbrain': {'dest': '/var/www/flatdb'},
            },
            'db': {
                'host': 'localhost',
                'name': 'flatdb',
                'user': 'flatdb_user',
                'password': 'db_secret',
            },
            'slack': {
                'channel_id': 'C12345',
            },
            'app': {
                'name': 'FlatDB',
                'support_email': 'contact@example.com',
                'base_url': {
                    'local': 'http://localhost/flatdb',
                    'akadbrain': 'https://flatdb.example.com',
                },
            },
            'extra_section': {
                'key': 'value',
            },
        },
        'multidb': {
            'targets': ['local', 'world4you'],
            'deploy': {
                'local': {'dest': '/var/www/multidb'},
                'world4you': {'ftp_base_dir': '/multidb/'},
            },
            'db': {
                'local': {'host': 'localhost', 'name': 'mdb', 'user': 'mu', 'password': 'mp'},
                'world4you': {'host': 'remotehost', 'name': 'remdb', 'user': 'ru', 'password': 'rp'},
            },
            'app': {
                'name': 'MultiDB',
                'support_email': 'contact@example.com',
                'base_url': {
                    'local': 'http://localhost/multidb',
                    'world4you': 'https://example.com/multidb',
                },
            },
        },
        'ownauth': {
            'targets': ['local'],
            'deploy': {'local': {'dest': '/var/www/ownauth'}},
            'db': {'host': 'localhost', 'name': 'ownauth', 'user': 'u', 'password': 'p'},
            'auth_db': {
                'socket': '/tmp/mysql.sock',
                'name': 'auth',
                'user': 'ownauth_user',
                'password': 'ownauth_pass',
            },
            'app': {
                'name': 'OwnAuth',
                'support_email': 'contact@example.com',
                'base_url': {'local': 'http://localhost/ownauth'},
            },
        },
    },
}


# ── resolve_db ─────────────────────────────────────────────────────────────────

def test_resolve_db_flat_returns_as_is():
    db = FIXTURE['apps']['flatdb']['db']
    assert resolve_db(db, 'local') == db

def test_resolve_db_per_target_local():
    db = FIXTURE['apps']['multidb']['db']
    result = resolve_db(db, 'local')
    assert result == {'host': 'localhost', 'name': 'mdb', 'user': 'mu', 'password': 'mp'}

def test_resolve_db_per_target_world4you():
    db = FIXTURE['apps']['multidb']['db']
    result = resolve_db(db, 'world4you')
    assert result == {'host': 'remotehost', 'name': 'remdb', 'user': 'ru', 'password': 'rp'}

def test_resolve_db_none_when_no_db():
    result = resolve_db(None, 'local')
    assert result is None


# ── resolve_app_config ─────────────────────────────────────────────────────────

def test_smtp_not_in_output():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert 'smtp' not in result

def test_slack_merges_bot_token_and_channel_id():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert result['slack']['bot_token'] == 'xoxb-test-token'
    assert result['slack']['channel_id'] == 'C12345'

def test_app_name_in_output():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert result['app']['name'] == 'FlatDB'

def test_app_support_email_in_output():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert result['app']['support_email'] == 'contact@example.com'

def test_base_url_resolved_for_local():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert result['app']['base_url'] == 'http://localhost/flatdb'

def test_base_url_resolved_for_akadbrain():
    result = resolve_app_config(FIXTURE, 'flatdb', 'akadbrain')
    assert result['app']['base_url'] == 'https://flatdb.example.com'

def test_flat_db_in_output():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert result['db']['name'] == 'flatdb'
    assert result['db']['password'] == 'db_secret'

def test_per_target_db_local():
    result = resolve_app_config(FIXTURE, 'multidb', 'local')
    assert result['db']['host'] == 'localhost'
    assert result['db']['name'] == 'mdb'

def test_per_target_db_world4you():
    result = resolve_app_config(FIXTURE, 'multidb', 'world4you')
    assert result['db']['host'] == 'remotehost'
    assert result['db']['name'] == 'remdb'

def test_auth_db_own():
    result = resolve_app_config(FIXTURE, 'ownauth', 'local')
    assert result['auth_db']['user'] == 'ownauth_user'
    assert result['auth_db']['socket'] == '/tmp/mysql.sock'

def test_extra_sections_pass_through():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert result['extra_section'] == {'key': 'value'}

def test_internal_keys_not_in_output():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert 'targets' not in result
    assert 'legacy_config' not in result

def test_app_color_passthrough():
    fixture = copy.deepcopy(FIXTURE)
    fixture['apps']['flatdb']['app']['color'] = '#d6a733'
    result = resolve_app_config(fixture, 'flatdb', 'local')
    assert result['app']['color'] == '#d6a733'

def test_app_color_absent_when_not_set():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert 'color' not in result.get('app', {})


# ── sanitize ───────────────────────────────────────────────────────────────────

def test_sanitize_replaces_password():
    result = sanitize({'password': 'secret'})
    assert result['password'] == 'your_password'

def test_sanitize_replaces_bot_token():
    result = sanitize({'bot_token': 'xoxb-real'})
    assert result['bot_token'] == 'your_bot_token'

def test_sanitize_preserves_non_credentials():
    result = sanitize({'host': 'smtp.example.com'})
    assert result['host'] == 'smtp.example.com'

def test_sanitize_preserves_integers():
    result = sanitize({'port': 587})
    assert result['port'] == 587

def test_sanitize_nested_dict():
    resolved = resolve_app_config(FIXTURE, 'flatdb', 'local')
    example = sanitize(resolved)
    assert example['db']['password'] == 'your_password'
    assert example['slack']['bot_token'] == 'your_bot_token'
    assert example['app']['base_url'] == 'http://localhost/flatdb'
    assert example['app']['name'] == 'FlatDB'


# ── generate_update_md ─────────────────────────────────────────────────────────

def test_update_md_mentions_legacy_path():
    md = generate_update_md('flatdb', 'config.ini')
    assert 'config.ini' in md

def test_update_md_mentions_app_name():
    md = generate_update_md('flatdb', 'config.ini')
    assert 'flatdb' in md

def test_update_md_mentions_new_files():
    md = generate_update_md('flatdb', 'config.ini')
    assert 'config.yaml' in md
    assert 'config.example.yaml' in md

def test_update_md_no_legacy():
    md = generate_update_md('flatdb', None)
    assert 'config.yaml' in md


# (write_app_svgs removed — per-app logo/favicon generation retired in favour of
#  central css_library/logos/ assets; see the TASK-19 harmonisation design doc.)
