"""Train Echo's small SNN on synthetic interval deviations; no player data required.

Python 3.12, torch 2.6.0, snntorch 0.9.4, numpy 2.2.6.
Run: python train_snn.py --output ./训练输出
Training is CPU-only and deterministic. No network is used by this script or app.
"""
import argparse
import hashlib
import json
import random
from pathlib import Path

import numpy as np
import torch
from torch import nn
import snntorch as snn
from snntorch import surrogate

SEED = 20261024
LABELS = ["steady", "fast", "slow", "uneven"]
STEPS, SLOTS, HIDDEN = 32, 16, 48


def encode(errors):
    """Nearest resampling to 16 slots, sign-separated deterministic rate code."""
    selected = [errors[int(k * (len(errors) - 1) / (SLOTS - 1) + 0.5)] for k in range(SLOTS)]
    counts = np.floor(np.minimum(np.abs(selected) / 0.5, 1) * STEPS + 0.5).astype(int)
    x = np.zeros((STEPS, SLOTS * 2), dtype=np.float32)
    for k, (error, count) in enumerate(zip(selected, counts)):
        for t in range(STEPS):
            x[t, k * 2 + int(error < 0)] = int((t + 1) * count // STEPS > t * count // STEPS)
    return x


def rule(errors):
    mean = float(np.mean(errors))
    spread = float(np.std(errors))
    if spread > 0.105:
        return 3
    if mean < -0.085:
        return 1
    if mean > 0.085:
        return 2
    return 0


def patterns(rng, count, seen):
    result = []
    while len(result) < count:
        n = rng.randint(4, 17)
        ticks = [0]
        for _ in range(n - 1):
            ticks.append(ticks[-1] + rng.randint(1, 3))
        lanes = [rng.randrange(4) for _ in ticks]
        identity = (tuple(ticks), tuple(lanes))
        if identity in seen:
            continue
        seen.add(identity)
        result.append({"ticks": ticks, "lanes": lanes, "bpm": rng.randint(60, 150)})
    return result


def dataset(rng, bases, repeats):
    xs, ys, records = [], [], []
    for index, base in enumerate(bases):
        expected = np.diff(base["ticks"]) * 30 / base["bpm"]
        for _ in range(repeats):
            for label in range(4):
                n = len(expected)
                if label == 0:
                    center, jitter = rng.uniform(-0.035, 0.035), rng.uniform(0.005, 0.035)
                    errors = np.array([center + rng.gauss(0, jitter) for _ in range(n)])
                elif label in (1, 2):
                    center = rng.uniform(0.13, 0.34) * (-1 if label == 1 else 1)
                    errors = np.array([center + rng.gauss(0, 0.025) for _ in range(n)])
                else:
                    # Intentionally mixed interval lengths, not a constant offset.
                    magnitude = rng.uniform(0.16, 0.38)
                    signs = [1 if k % 2 else -1 for k in range(n)]
                    rng.shuffle(signs)
                    errors = np.array([sign * magnitude + rng.gauss(0, 0.025) for sign in signs])
                errors = np.clip(errors, -0.49, 0.49)
                # Round taps to the same 10 ms grid used on-device before deriving errors.
                actual = np.cumsum(np.r_[0, expected * (1 + errors)])
                actual = np.floor(actual / 0.01 + 0.5) * 0.01
                quantized_errors = np.diff(actual) / expected - 1
                xs.append(encode(quantized_errors)); ys.append(label)
                records.append({"base": index, "ticks": base["ticks"], "lanes": base["lanes"],
                                "bpm": base["bpm"], "times": actual.tolist(),
                                "errors": quantized_errors.tolist(), "label": label})
    return torch.from_numpy(np.stack(xs)), torch.tensor(ys), records


class Net(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(32, HIDDEN)
        self.lif = snn.Leaky(beta=0.9, threshold=1.0, spike_grad=surrogate.fast_sigmoid(),
                             reset_mechanism="subtract", reset_delay=False)
        self.fc2 = nn.Linear(HIDDEN, 4)

    def forward(self, x, trace=False):
        membrane = torch.zeros((x.shape[0], HIDDEN))
        spikes, potentials = [], []
        for t in range(STEPS):
            spike, membrane = self.lif(self.fc1(x[:, t]), membrane)
            spikes.append(spike)
            if trace:
                potentials.append(membrane)
        activity = torch.stack(spikes, dim=1)
        output = self.fc2(activity.mean(dim=1))
        return (output, activity, torch.stack(potentials, dim=1)) if trace else output


def metrics(predictions, targets):
    matrix = np.zeros((4, 4), dtype=int)
    for true, pred in zip(targets, predictions):
        matrix[int(true), int(pred)] += 1
    f1s = [2 * matrix[k, k] / max(1, matrix[k].sum() + matrix[:, k].sum()) for k in range(4)]
    return {"accuracy": float(np.trace(matrix) / matrix.sum()), "macroF1": float(np.mean(f1s)),
            "confusion": matrix.tolist()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--epochs", type=int, default=55)
    args = parser.parse_args()
    torch.manual_seed(SEED); np.random.seed(SEED); random.seed(SEED)
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    rng, seen = random.Random(SEED), set()
    train_bases = patterns(rng, 180, seen)
    val_bases = patterns(rng, 36, seen)
    test_bases = patterns(rng, 48, seen)
    tx, ty, _ = dataset(rng, train_bases, 4)
    vx, vy, _ = dataset(rng, val_bases, 2)
    sx, sy, records = dataset(rng, test_bases, 3)
    net = Net(); optimizer = torch.optim.Adam(net.parameters(), lr=0.003)
    best_loss, best_state = float("inf"), None
    for epoch in range(args.epochs):
        net.train(); total = 0
        for batch in torch.randperm(len(tx)).split(128):
            output = net(tx[batch]); loss = nn.functional.cross_entropy(output, ty[batch])
            optimizer.zero_grad(); loss.backward(); nn.utils.clip_grad_norm_(net.parameters(), 1)
            optimizer.step(); total += loss.item() * len(batch)
        net.eval()
        with torch.no_grad():
            val_output = torch.cat([net(batch) for batch in vx.split(128)])
            val_loss = nn.functional.cross_entropy(val_output, vy).item()
            accuracy = (val_output.argmax(1) == vy).float().mean().item()
        if val_loss < best_loss:
            best_loss = val_loss
            best_state = {key: value.clone() for key, value in net.state_dict().items()}
        if epoch % 5 == 0 or epoch == args.epochs - 1:
            print(f"epoch={epoch + 1} loss={total / len(tx):.4f} val_loss={val_loss:.4f} val_acc={accuracy:.3f}", flush=True)
    net.load_state_dict(best_state); net.eval()
    with torch.no_grad():
        logits = torch.cat([net(batch) for batch in sx.split(128)])
        probabilities = logits.softmax(1)
        snn_metrics = metrics(logits.argmax(1).tolist(), sy.tolist())
    rule_metrics = metrics([rule(r["errors"]) for r in records], sy.tolist())
    report = {"seed": SEED, "dataSource": "synthetic_only", "humanSamples": 0,
              "trainCount": len(tx), "validationCount": len(vx), "testCount": len(sx),
              "trainPatterns": 180, "validationPatterns": 36, "testPatterns": 48,
              "split": "disjoint_base_patterns", "labels": LABELS,
              "snn": snn_metrics, "rule": rule_metrics,
              "note": "Synthetic benchmark only; not evidence of human accuracy or energy savings."}
    model = {"schema": 1, "modelID": "echo-interval-lif-v1", "labels": LABELS,
             "steps": STEPS, "slots": SLOTS, "hidden": HIDDEN, "beta": 0.9, "threshold": 1.0,
             "errorScale": 0.5, "gridSeconds": 0.01,
             "w1": net.fc1.weight.detach().tolist(), "b1": net.fc1.bias.detach().tolist(),
             "w2": net.fc2.weight.detach().tolist(), "b2": net.fc2.bias.detach().tolist(),
             "benchmark": report}
    args.output.mkdir(parents=True, exist_ok=True)
    model_file = args.output / "EchoSNN.json"
    model_file.write_text(json.dumps(model, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    verification = []
    with torch.no_grad():
        for label in range(4):
            candidates = [i for i, r in enumerate(records) if r["label"] == label][:12]
            for i in candidates:
                output, spikes, membrane = net(sx[i:i + 1], trace=True)
                verification.append({**records[i], "input": sx[i].tolist(), "logits": output[0].tolist(),
                                     "spikes": spikes[0].int().tolist(), "membrane": membrane[0].tolist()})
    (args.output / "SNNParity.json").write_text(json.dumps(verification, separators=(",", ":")), encoding="utf-8")
    (args.output / "SNNBenchmark.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    print("model_sha256=" + hashlib.sha256(model_file.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
