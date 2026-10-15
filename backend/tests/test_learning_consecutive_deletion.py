from test_learning_deletion import add_fixed, request, latest, consume
from test_meditation_sync import context
from test_api import auth, client

def test_two_deletions_before_first_fit_keep_remaining_twenty_rebuild_durable(tmp_path, monkeypatch):
    token, profile, _ = context(tmp_path, monkeypatch)
    retained = [add_fixed(token, profile, target)[0] for target in range(10) for _ in range(2)]
    extra_a = add_fixed(token, profile, 4)[0]
    extra_b = add_fixed(token, profile, 6)[0]
    request(token, extra_b)
    for sid in [extra_a, extra_b]:
        response = client.post('/v1/sessions/delete', headers=auth(token), json={'session_ids':[sid]})
        assert response.status_code == 200, response.text
        assert latest(token)['status'] == 'revoked'
    consume()
    actual = latest(token)
    assert actual['status'] == 'ready', 'second deletion cancelled the first rebuild without durable remaining-data replacement'
    assert actual['validation']['session_count'] == 20
    assert set(actual['included_session_ids']) == set(retained)
