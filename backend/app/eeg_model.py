"""Versioned, source-independent EEG extraction and session-level ridge math."""
import math
from collections import Counter, defaultdict
import numpy as np

PREPROCESSING = 'meditation-eeg-1'
QUALITY = '2026.4-unverified'
NUMERIC = ['log_theta_alpha', 'log_beta_alpha', 'carrier_hz', 'tone_gain', 'background_gain']


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def second_bin(seconds):
    if not finite(seconds) or not 0 < seconds <= 600:
        return None
    second = math.ceil(seconds - 1e-9)
    return second if 1 <= second <= 600 else None


def extract_minutes(frames):
    """One canonical frame/bin;50 eligible seconds are the fixed denominator."""
    mapped = [f for f in frames if isinstance(f, dict) and f.get('playback_active') is True
        and second_bin(f.get('active_time_seconds')) is not None and finite(f.get('time_seconds'))]
    mapped.sort(key=lambda f: (f['active_time_seconds'], f['time_seconds']))
    canonical = {}
    for frame in mapped:
        canonical.setdefault(second_bin(frame['active_time_seconds']), frame)
    periods = defaultdict(lambda: defaultdict(dict))
    for second, frame in canonical.items():
        minute, within = divmod(second - 1, 60)
        if within < 10 or frame.get('rejected') is not False:
            continue
        channels = frame.get('channels')
        if not isinstance(channels, list):
            continue
        names = Counter(c.get('name') for c in channels if isinstance(c, dict) and isinstance(c.get('name'), str))
        for channel in channels:
            if not isinstance(channel, dict):
                continue
            name = channel.get('name')
            if not isinstance(name, str) or names[name] != 1 or channel.get('valid') is not True:
                continue
            powers = [channel.get('absolute_' + band) for band in ('theta', 'alpha', 'beta')]
            if not all(finite(v) and v > 0 for v in powers):
                continue
            theta, alpha, beta = powers
            periods[minute][name][second] = [math.log(theta) - math.log(alpha), math.log(beta) - math.log(alpha)]
    result = []
    for minute in sorted(periods):
        eligible = {name: values for name, values in periods[minute].items() if len(values) >= 40}
        if len(eligible) < 2:
            continue
        pairs = [pair for values in eligible.values() for pair in values.values()]
        result.append(dict(minute=minute, features=np.mean(pairs, axis=0).tolist(),
            coverage={name: len(values) for name, values in sorted(eligible.items())}))
    return result


def fit_ridge(x, y):
    x, y = np.asarray(x, dtype=np.float64), np.asarray(y, dtype=np.float64)
    if x.ndim != 2 or y.ndim != 1 or len(x) != len(y) or len(x) == 0 or not np.isfinite(x).all() or not np.isfinite(y).all():
        raise ValueError('Finite training rows are required')
    means = np.mean(x, axis=0)
    centered = x - means
    magnitude = np.max(np.abs(centered), axis=0)
    denominator = np.where(magnitude == 0, 1., magnitude)
    # Population scaling, normalized first to avoid squared-value underflow.
    scales = magnitude * np.std(centered / denominator, axis=0, ddof=0)
    scales[np.ptp(x, axis=0) == 0] = 1.
    if not np.isfinite(scales).all() or np.any(scales <= 0):
        raise ValueError('Finite nonzero population scales required')
    standardized = centered / scales
    intercept = float(np.mean(y))
    augmented = np.concatenate([standardized, np.eye(x.shape[1])], axis=0)
    target = np.concatenate([y - intercept, np.zeros(x.shape[1])])
    coefficients = np.linalg.lstsq(augmented, target, rcond=None)[0]
    if not np.isfinite(coefficients).all():
        raise ValueError('Non-finite ridge coefficients')
    return dict(means=means.tolist(), scales=scales.tolist(), coefficients=coefficients.tolist(), intercept=intercept)


def predict_ridge(fit, row):
    value = float(fit['intercept'] + np.dot(fit['coefficients'],
        (np.asarray(row, dtype=np.float64) - fit['means']) / fit['scales']))
    if not math.isfinite(value):
        raise ValueError('Non-finite prediction')
    return value


def design(rows, backgrounds, eyes, context_only=False):
    return [[*([] if context_only else row['features']),
        row['carrier_hz'], row['tone_gain'], row['background_gain'],
        *[float(row['background_asset_id'] == bg) for bg in backgrounds],
        *[float(row['eye_state'] == eye) for eye in eyes]] for row in rows]


def vocabulary(rows):
    return sorted({row['background_asset_id'] for row in rows}), sorted({row['eye_state'] for row in rows})


def train_model(rows):
    """Exactly one equally weighted row/target per session, fold-local fitting."""
    base = dict(schema_version=1, preprocessing_version=PREPROCESSING, quality_version=QUALITY,
        protocol_version='meditation-1', included_session_ids=[row['session_id'] for row in rows],
        evidence=[dict(session_id=r['session_id'], checksum_sha256=r['checksum_sha256'], feedback_revision=r['feedback_revision']) for r in rows])
    gates = dict(session_count=len(rows) >= 20, mae=False, correlation=False, improvement=False)
    base['validation'] = dict(session_count=len(rows), mae=None, correlation=None, context_mae=None, gates=gates)
    if len(rows) < 20:
        return base | dict(status='insufficient', reasons=['At least twenty usable fixed sessions are required'])
    targets = np.asarray([r['target'] for r in rows], dtype=np.float64)
    predictions, context_predictions = [], []
    for held in range(len(rows)):
        training = rows[:held] + rows[held + 1:]
        bg, eyes = vocabulary(training)
        y = [r['target'] for r in training]
        for context_only, output in [(False, predictions), (True, context_predictions)]:
            fit = fit_ridge(design(training, bg, eyes, context_only), y)
            output.append(predict_ridge(fit, design([rows[held]], bg, eyes, context_only)[0]))
    base['validation'] = validate_predictions(targets, predictions, context_predictions, len(rows))
    gates = base['validation']['gates']
    backgrounds, eyes = vocabulary(rows)
    fit = fit_ridge(design(rows, backgrounds, eyes), targets)
    contexts = Counter((r['background_asset_id'], r['eye_state']) for r in rows)
    base.update(fit, backgrounds=backgrounds, eyes=eyes,
        feature_order=NUMERIC + ['background:' + bg for bg in backgrounds] + ['eye:' + eye for eye in eyes],
        training_ranges={name: [min(r[name] for r in rows), max(r[name] for r in rows)] for name in NUMERIC[2:]},
        supported_contexts=[dict(background_asset_id=bg, eye_state=eye, session_count=count) for (bg, eye), count in sorted(contexts.items())],
        fixed_minutes=[dict(session_id=r['session_id'], profile_version_id=r['profile_version_id'],
            background_asset_id=r['background_asset_id'], eye_state=r['eye_state'], carrier_hz=r['carrier_hz'],
            tone_gain=r['tone_gain'], background_gain=r['background_gain'], fixed_action=r['fixed_action'],
            minute=m['minute'], features=m['features'], score=predict_ridge(fit, design([r | {'features':m['features']}], backgrounds, eyes)[0]))
            for r in rows for m in r['minutes']],
        status='ready' if all(gates.values()) else 'failed_validation',
        reasons=[name + ' validation gate failed' for name, passed in gates.items() if not passed])
    return base


def validate_predictions(targets, predictions, context_predictions, session_count):
    targets = np.asarray(targets, dtype=np.float64)
    predictions = np.asarray(predictions, dtype=np.float64)
    context_predictions = np.asarray(context_predictions, dtype=np.float64)
    if targets.ndim != 1 or not len(targets) or predictions.shape != targets.shape or context_predictions.shape != targets.shape:
        raise ValueError('Matched held-out session vectors required')
    if not all(np.isfinite(v).all() for v in [targets,predictions,context_predictions]):
        raise ValueError('Finite held-out predictions required')
    mae = float(np.mean(np.abs(predictions-targets)))
    context_mae = float(np.mean(np.abs(context_predictions-targets)))
    correlation = None
    if np.ptp(targets)>0 and np.ptp(predictions)>0:
        value = float(np.corrcoef(targets,predictions)[0,1])
        if math.isfinite(value):
            correlation = value
    return dict(session_count=session_count,mae=mae,correlation=correlation,context_mae=context_mae,
        held_out_predictions=predictions.tolist(),context_predictions=context_predictions.tolist(),
        gates=dict(session_count=session_count>=20,mae=mae<=2.,correlation=correlation is not None and correlation>=.5,
            improvement=context_mae>0 and mae<=.8*context_mae))
