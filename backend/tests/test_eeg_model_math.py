"""Independent numerical examples; no generated expected production output."""
import math
import pytest
from app.eeg_model import extract_minutes, fit_ridge, predict_ridge


def channel(name, theta=4, alpha=2, beta=8, valid=True):
    return dict(name=name, valid=valid, absolute_theta=theta, absolute_alpha=alpha, absolute_beta=beta)


def frames(endpoints, **changes):
    return [dict(time_seconds=100 + t, active_time_seconds=t, playback_active=True, rejected=False,
        channels=[channel('A'), channel('B', 2, 2, 2), channel('bad', 10000, 1, 10000, False)]) | changes for t in endpoints]


def test_eligible_minute_uses_independent_log_ratio_examples_and_50_second_coverage():
    minute = extract_minutes(frames(range(11, 61)))[0]
    assert minute['coverage'] == {'A': 50, 'B': 50}
    assert minute['features'] == pytest.approx([0.34657359027997265, 0.6931471805599453])
    assert extract_minutes(frames(range(21, 61)))[0]['coverage'] == {'A': 40, 'B': 40}
    assert extract_minutes(frames(range(22, 61))) == []
    assert extract_minutes(frames(range(22, 61)) * 3) == []
    # Fractional endpoints are binned once, not rejected for being off-grid.
    assert extract_minutes(frames([t + .25 for t in range(10, 60)]))[0]['coverage'] == {'A': 50, 'B': 50}
    assert extract_minutes(frames(range(11, 61), rejected=True)) == []


def test_ridge_sum_loss_unpenalized_intercept_has_closed_form():
    fit = fit_ridge([[1.], [3.]], [2., 4.])
    assert fit['means'] == [2.]
    assert fit['scales'] == [1.]
    assert fit['coefficients'] == pytest.approx([2 / 3])
    assert fit['intercept'] == 3.
    assert [predict_ridge(fit, [x]) for x in [1., 2., 3.]] == pytest.approx([7 / 3, 3., 11 / 3])


def test_session_weight_and_fold_validation_from_synthetic_subjective_evidence():
    from app.eeg_model import train_model
    rows = [dict(session_id=f'synthetic-{r}-{bg}', features=[(r - 4.5) / 3, -.1 if bg == 'rain' else .1],
        target=float(r), background_asset_id=bg, eye_state='closed', carrier_hz=220., tone_gain=.2, background_gain=.6,
        minutes=[dict(minute=m, features=[(r - 4.5) / 3, -.1 if bg == 'rain' else .1]) for m in range(1 if bg == 'rain' else 10)],
        fixed_action='control', profile_version_id='profile', checksum_sha256='a'*64, feedback_revision=1)
        for r in range(10) for bg in ['rain', 'forest']]
    model = train_model(rows)
    assert model['validation']['session_count'] == 20
    assert model['status'] == 'ready'
    assert model['validation']['mae'] < .2
    assert model['validation']['correlation'] > .99
    assert model['validation']['context_mae'] > 2
    assert model['training_ranges']['carrier_hz'] == [220.,220.]
    assert sorted(c['session_count'] for c in model['supported_contexts']) == [10,10]
    assert len(model['fixed_minutes']) == 110
    assert train_model(rows[:-1])['status'] == 'insufficient'
    constant = [row | {'target':5.} for row in rows]
    failed = train_model(constant)
    assert failed['status'] == 'failed_validation'
    assert failed['validation']['correlation'] is None
    assert not failed['validation']['gates']['correlation']


def test_validation_gates_use_literal_held_out_errors_and_degenerate_cases():
    from app.eeg_model import validate_predictions
    # Targets [0,2,4,6], full errors [.5,.5,.5,.5], context errors1.
    v=validate_predictions([0,2,4,6],[.5,2.5,4.5,6.5],[1,3,5,7],20)
    assert v['mae']==.5 and v['context_mae']==1 and v['correlation']==pytest.approx(1)
    assert all(v['gates'].values())
    assert not validate_predictions([0,2,4,6],[3,5,7,9],[4,6,8,10],20)['gates']['mae']
    assert not validate_predictions([0,2,4,6],[6,4,2,0],[7,5,3,1],20)['gates']['correlation']
    assert not validate_predictions([0,2,4,6],[1,3,5,7],[1,3,5,7],20)['gates']['improvement']
    zero=validate_predictions([5,5,5,5],[5,5,5,5],[5,5,5,5],20)
    assert zero['correlation'] is None and not zero['gates']['improvement']


def test_leave_one_session_out_scaling_matches_independent_closed_form():
    from app.eeg_model import train_model
    rows=[dict(session_id=f'literal-{r}',features=[float(r),0.],target=r/2,
        background_asset_id='one',eye_state='closed',carrier_hz=220.,tone_gain=.2,background_gain=.6,
        minutes=[],fixed_action='control',profile_version_id='profile',checksum_sha256='a'*64,feedback_revision=1) for r in range(20)]
    result=train_model(rows)
    # Each fold has19 rows. Standardized ridge shrinks its sole varying slope
    # by19/20, around that fold's own mean. Held-out0=>.25, held-out19=>9.25.
    assert result['validation']['held_out_predictions'][0]==pytest.approx(.25)
    assert result['validation']['held_out_predictions'][19]==pytest.approx(9.25)
    assert result['validation']['mae']==pytest.approx(.13157894736842105)
    assert result['validation']['context_mae']==pytest.approx(2.6315789473684212)
    assert result['status']=='ready'


def test_paused_unmapped_invalid_canonical_and_duplicate_channels_never_supply_coverage():
    assert extract_minutes(frames(range(11,61),playback_active=False))==[]
    assert extract_minutes(frames(range(11,61),active_time_seconds=None))==[]
    # A denser valid later frame cannot replace the first canonical invalid frame.
    invalid=frames(range(11,61),rejected=True)
    later=[f | {'time_seconds':f['time_seconds']+.1} for f in frames(range(11,61))]
    assert extract_minutes(invalid+later)==[]
    assert extract_minutes(frames(range(11,61),channels=[channel('A'),channel('B'),channel('A')]))==[]


def test_population_scaling_does_not_underflow_for_small_finite_settings():
    fit=fit_ridge([[1e-200],[3e-200]],[2.,4.])
    assert fit['means'][0]==pytest.approx(2e-200,abs=0)
    assert fit['scales'][0]==pytest.approx(1e-200,abs=0)
    assert fit['coefficients'][0]==pytest.approx(2/3)
    assert predict_ridge(fit,[1e-200])==pytest.approx(7/3)
