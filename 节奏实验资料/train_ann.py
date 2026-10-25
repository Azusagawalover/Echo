"""Matched ANN baseline: same base-pattern splits and encoded samples as SNN v1.

Run: python train_ann.py --snn ../Echo/Resources/EchoSNN.json --output ./ANN训练输出
ANN sees the time-mean of the identical 32-channel pulse sequence; SNN sees all steps.
Both networks have 1,780 trainable parameters. No player records are read or uploaded.
"""
import argparse
import hashlib
import json
import random
from pathlib import Path

import numpy as np
import torch
from torch import nn
from train_snn import SEED, LABELS, Net, patterns, dataset, metrics, rule


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--snn', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    torch.manual_seed(SEED); np.random.seed(SEED)
    rng, seen = random.Random(SEED), set()
    train_bases, val_bases, test_bases = (patterns(rng, n, seen) for n in [180, 36, 48])
    tx, ty, _ = dataset(rng, train_bases, 4)
    vx, vy, _ = dataset(rng, val_bases, 2)
    sx, sy, records = dataset(rng, test_bases, 3)
    snn_data = json.loads(args.snn.read_text())
    snn = Net()
    with torch.no_grad():
        for layer, prefix in [(snn.fc1, '1'), (snn.fc2, '2')]:
            layer.weight.copy_(torch.tensor(snn_data['w' + prefix]))
            layer.bias.copy_(torch.tensor(snn_data['b' + prefix]))
        snn_output = torch.cat([snn(batch) for batch in sx.split(128)])
    snn_metrics = metrics(snn_output.argmax(1).tolist(), sy.tolist())
    assert snn_metrics == snn_data['benchmark']['snn'], 'Dataset or baseline changed'
    torch.manual_seed(SEED + 1)
    ann = nn.Sequential(nn.Linear(32, 48), nn.ReLU(), nn.Linear(48, 4))
    optimizer = torch.optim.Adam(ann.parameters(), lr=0.003)
    train, val, test = tx.mean(1), vx.mean(1), sx.mean(1)
    best_loss, best = float('inf'), None
    for epoch in range(55):
        for batch in torch.randperm(len(train)).split(128):
            output = ann(train[batch]); loss = nn.functional.cross_entropy(output, ty[batch])
            optimizer.zero_grad(); loss.backward(); optimizer.step()
        with torch.no_grad():
            val_output = ann(val)
            val_loss = nn.functional.cross_entropy(val_output, vy).item()
        if val_loss < best_loss:
            best_loss = val_loss
            best = {k: v.clone() for k, v in ann.state_dict().items()}
        if epoch % 10 == 0:
            print(f'epoch={epoch+1} val_loss={val_loss:.5f}', flush=True)
    ann.load_state_dict(best); ann.eval()
    with torch.no_grad():
        output = ann(test)
    ann_metrics = metrics(output.argmax(1).tolist(), sy.tolist())
    report = {**snn_data['benchmark'], 'ann': ann_metrics, 'snn': snn_metrics,
              'rule': metrics([rule(r['errors']) for r in records], sy.tolist()),
              'datasetSHA256': hashlib.sha256(sx.numpy().tobytes() + sy.numpy().tobytes()).hexdigest(),
              'input': 'same_pulse_samples_ANN_time_mean_SNN_temporal',
              'snnModelSHA256': hashlib.sha256(args.snn.read_bytes()).hexdigest(),
              'annSeed': SEED + 1, 'epochs': 55, 'parameters': {'ann': 1780, 'snn': 1780},
              'note': 'Controlled synthetic benchmark, no human-accuracy or energy claim.'}
    model = {'schema': 1, 'modelID': 'echo-interval-mlp-v1', 'labels': LABELS, 'inputs': 32, 'hidden': 48,
             'w1': ann[0].weight.detach().tolist(), 'b1': ann[0].bias.detach().tolist(),
             'w2': ann[2].weight.detach().tolist(), 'b2': ann[2].bias.detach().tolist(), 'benchmark': report}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'EchoANN.json').write_text(json.dumps(model, ensure_ascii=False, separators=(',', ':')))
    (args.output / 'ThreeWayBenchmark.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    fixtures = []
    with torch.no_grad():
        for label in range(4):
            for i in [i for i, r in enumerate(records) if r['label'] == label][:12]:
                fixtures.append({'input': sx[i].tolist(), 'features': test[i].tolist(),
                                 'logits': output[i].tolist(), 'label': label})
    (args.output / 'ANNParity.json').write_text(json.dumps(fixtures, separators=(',', ':')))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
