#!/usr/bin/env python3
"""Calculate required parallels for each water grade."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from decimal import Decimal, ROUND_CEILING, ROUND_FLOOR
from pathlib import Path
from typing import Any


GRADE_COUNT = 8
LITERS_PER_INPUT = 1000
LITERS_PER_SUCCESS = Decimal("900")
BOOST_CONSUMPTION = Decimal("90")
BOOST_SUCCESS_BONUS = Decimal("0.15")
MAX_SUCCESS = Decimal("1.0")
MAX_SIGNED_INT = 2_147_483_647
MAX_PARALLEL_CAP = MAX_SIGNED_INT // LITERS_PER_INPUT
OUTPUT_PATTERN = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*([kmbKMB]?)\s*$")
SUFFIX_MULTIPLIERS = {
    "": Decimal("1"),
    "k": Decimal("1000"),
    "m": Decimal("1000000"),
    "b": Decimal("1000000000"),
}


class WaterCalcError(ValueError):
    """Raised when the input file or calculation is invalid."""


@dataclass(frozen=True)
class StageConfig:
    grade: int
    boost: bool
    success: Decimal
    target_liters: int


@dataclass(frozen=True)
class StageResult:
    grade: int
    boost: bool
    target_liters: int
    effective_success: Decimal
    net_liters_per_parallel: Decimal
    max_feasible_parallels: int
    required_net_liters: int
    requested_parallels: int
    actual_parallels: int
    actual_net_liters: Decimal
    target_achieved_liters: Decimal
    target_shortfall_liters: Decimal
    previous_grade_input: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Calculate required parallels for chained water grades."
    )
    parser.add_argument(
        "path",
        nargs="?",
        default="water.json",
        help="Path to the water stage JSON file (default: water.json).",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run internal calculation checks and exit.",
    )
    return parser.parse_args()


def parse_output_liters(value: Any) -> int:
    if isinstance(value, (int, float)):
        text = str(value)
    elif isinstance(value, str):
        text = value
    else:
        raise WaterCalcError(f"Unsupported output value: {value!r}")

    match = OUTPUT_PATTERN.match(text)
    if not match:
        raise WaterCalcError(
            f"Invalid output literal {value!r}. Use liters or suffixes k/m/b."
        )

    number_text, suffix = match.groups()
    liters = Decimal(number_text) * SUFFIX_MULTIPLIERS[suffix.lower()]
    if liters != liters.to_integral_value():
        raise WaterCalcError(f"Output literal {value!r} does not resolve to whole liters.")
    return int(liters)


def parse_stage(raw: Any, index: int) -> StageConfig:
    if not isinstance(raw, dict):
        raise WaterCalcError(f"Stage {index} must be an object.")

    required_keys = {"grade", "boost", "success", "output"}
    missing = required_keys - raw.keys()
    if missing:
        raise WaterCalcError(f"Stage {index} is missing keys: {', '.join(sorted(missing))}.")

    try:
        grade = int(raw["grade"])
    except (TypeError, ValueError) as exc:
        raise WaterCalcError(f"Stage {index} has invalid grade: {raw['grade']!r}") from exc

    boost = raw["boost"]
    if not isinstance(boost, bool):
        raise WaterCalcError(f"Stage {index} boost must be true/false.")

    try:
        success = Decimal(str(raw["success"]))
    except Exception as exc:  # pragma: no cover - Decimal error types vary.
        raise WaterCalcError(f"Stage {index} has invalid success: {raw['success']!r}") from exc

    if success < 0:
        raise WaterCalcError(f"Stage {index} success cannot be negative.")

    target_liters = parse_output_liters(raw["output"])
    return StageConfig(
        grade=grade,
        boost=boost,
        success=success,
        target_liters=target_liters,
    )


def load_stages(path: Path) -> list[StageConfig]:
    try:
        raw_data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise WaterCalcError(f"Input file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise WaterCalcError(f"Invalid JSON in {path}: {exc}") from exc

    if not isinstance(raw_data, list):
        raise WaterCalcError("Top-level JSON value must be a list.")

    stages = [parse_stage(item, index + 1) for index, item in enumerate(raw_data)]

    if len(stages) != GRADE_COUNT:
        raise WaterCalcError(
            f"Expected exactly {GRADE_COUNT} stages, found {len(stages)}."
        )

    grades = [stage.grade for stage in stages]
    expected = list(range(1, GRADE_COUNT + 1))
    if grades != expected:
        raise WaterCalcError(
            f"Stages must be ordered exactly by grade {expected}; found {grades}."
        )

    if len(set(grades)) != len(grades):
        raise WaterCalcError("Duplicate grades detected in input.")

    return stages


def ceil_decimal(value: Decimal) -> int:
    return int(value.to_integral_value(rounding=ROUND_CEILING))


def floor_decimal(value: Decimal) -> int:
    return int(value.to_integral_value(rounding=ROUND_FLOOR))


def calculate_stage_metrics(
    stage: StageConfig,
) -> tuple[Decimal, Decimal]:
    effective_success = min(
        MAX_SUCCESS,
        stage.success + (BOOST_SUCCESS_BONUS if stage.boost else Decimal("0")),
    )
    net_liters_per_parallel = (
        LITERS_PER_SUCCESS * effective_success
        - (BOOST_CONSUMPTION if stage.boost else Decimal("0"))
    )
    if net_liters_per_parallel <= 0:
        raise WaterCalcError(
            f"Grade {stage.grade} has non-positive net liters per parallel: "
            f"{format_decimal(net_liters_per_parallel)}."
        )
    return effective_success, net_liters_per_parallel


def calculate_results(
    stages: list[StageConfig], parallel_cap: int = MAX_PARALLEL_CAP
) -> list[StageResult]:
    metrics = [calculate_stage_metrics(stage) for stage in stages]
    max_feasible_parallels: list[int] = []
    downstream_capacity = Decimal("Infinity")

    for index, stage in enumerate(stages):
        if index == 0:
            max_parallels = parallel_cap
        else:
            max_parallels = min(parallel_cap, floor_decimal(downstream_capacity))

        max_feasible_parallels.append(max_parallels)
        max_net_liters = Decimal(max_parallels) * metrics[index][1]
        surplus_after_target = max(Decimal("0"), max_net_liters - Decimal(stage.target_liters))
        downstream_capacity = surplus_after_target / Decimal(LITERS_PER_INPUT)

    actual_parallels = [0] * len(stages)
    next_stage_input = 0

    for index in range(len(stages) - 1, -1, -1):
        stage = stages[index]
        _, net_liters_per_parallel = metrics[index]
        required_net_liters = stage.target_liters + next_stage_input
        requested_parallels = ceil_decimal(
            Decimal(required_net_liters) / net_liters_per_parallel
        )
        actual = min(requested_parallels, max_feasible_parallels[index])
        actual_parallels[index] = actual
        next_stage_input = actual * LITERS_PER_INPUT

    results: list[StageResult] = []
    for index, stage in enumerate(stages):
        effective_success, net_liters_per_parallel = metrics[index]
        next_input = (
            actual_parallels[index + 1] * LITERS_PER_INPUT
            if index + 1 < len(stages)
            else 0
        )
        required_net_liters = stage.target_liters + next_input
        requested_parallels = ceil_decimal(
            Decimal(required_net_liters) / net_liters_per_parallel
        )
        actual = actual_parallels[index]
        actual_net_liters = Decimal(actual) * net_liters_per_parallel
        remaining_after_next = max(
            Decimal("0"), actual_net_liters - Decimal(next_input)
        )
        target_achieved_liters = min(Decimal(stage.target_liters), remaining_after_next)
        target_shortfall_liters = Decimal(stage.target_liters) - target_achieved_liters

        results.append(
            StageResult(
                grade=stage.grade,
                boost=stage.boost,
                target_liters=stage.target_liters,
                effective_success=effective_success,
                net_liters_per_parallel=net_liters_per_parallel,
                max_feasible_parallels=max_feasible_parallels[index],
                required_net_liters=required_net_liters,
                requested_parallels=requested_parallels,
                actual_parallels=actual,
                actual_net_liters=actual_net_liters,
                target_achieved_liters=target_achieved_liters,
                target_shortfall_liters=target_shortfall_liters,
                previous_grade_input=actual * LITERS_PER_INPUT,
            )
        )

    return results


def format_int(value: int) -> str:
    return f"{value:,}"


def format_decimal(value: Decimal) -> str:
    normalized = value.normalize()
    text = format(normalized, "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text or "0"


def format_decimal_with_commas(value: Decimal) -> str:
    text = format_decimal(value)
    if "." in text:
        whole, fractional = text.split(".", 1)
        return f"{int(whole):,}.{fractional}"
    return f"{int(text):,}"


def format_success(value: Decimal) -> str:
    percentage = (value * Decimal("100")).quantize(Decimal("0.01"))
    text = format(percentage, "f").rstrip("0").rstrip(".")
    return f"{text}%"


def render_table(results: list[StageResult]) -> str:
    rows = [
        [
            str(result.grade),
            "yes" if result.boost else "no",
            format_int(result.target_liters),
            format_success(result.effective_success),
            format_decimal(result.net_liters_per_parallel),
            format_int(result.required_net_liters),
            format_int(result.requested_parallels),
            format_int(result.actual_parallels),
            format_decimal_with_commas(result.actual_net_liters),
            format_decimal_with_commas(result.target_shortfall_liters),
            format_int(result.previous_grade_input),
        ]
        for result in results
    ]

    headers = [
        "Grade",
        "Boost",
        "Target (L)",
        "Eff. Success",
        "Net L/Parallel",
        "Required Net (L)",
        "Req. Par.",
        "Used Par.",
        "Actual Net (L)",
        "Shortfall (L)",
        "Prev Input (L)",
    ]
    widths = [
        max(len(header), *(len(row[index]) for row in rows))
        for index, header in enumerate(headers)
    ]

    def fmt_row(values: list[str]) -> str:
        return "  ".join(
            value.rjust(widths[index]) if index != 1 else value.ljust(widths[index])
            for index, value in enumerate(values)
        )

    lines = [fmt_row(headers), fmt_row(["-" * width for width in widths])]
    lines.extend(fmt_row(row) for row in rows)
    return "\n".join(lines)


def render_limit_summary(results: list[StageResult]) -> str:
    limited = [result for result in results if result.actual_parallels < result.requested_parallels]
    if not limited:
        return ""

    lines = ["Capacity-limited stages:"]
    for result in limited:
        lines.append(
            f"Grade {result.grade}: needed {format_int(result.requested_parallels)} parallels, "
            f"ran {format_int(result.actual_parallels)}, "
            f"target shortfall {format_decimal_with_commas(result.target_shortfall_liters)} L"
        )
    return "\n".join(lines)


def run_self_tests() -> None:
    assert parse_output_liters("50m") == 50_000_000
    assert parse_output_liters("1.5k") == 1_500

    boosted = StageConfig(grade=1, boost=True, success=Decimal("0.95"), target_liters=0)
    normal = StageConfig(grade=2, boost=False, success=Decimal("1.0"), target_liters=0)
    boosted_result, normal_result = calculate_results([boosted, normal])
    assert boosted_result.effective_success == Decimal("1.0")
    assert boosted_result.net_liters_per_parallel == Decimal("810")
    assert normal_result.required_net_liters == 0
    assert normal_result.actual_parallels == 0

    stages = [
        StageConfig(grade=1, boost=False, success=Decimal("1.0"), target_liters=0),
        StageConfig(grade=2, boost=False, success=Decimal("1.0"), target_liters=901),
    ]
    first, second = calculate_results(stages)
    assert second.actual_parallels == 2
    assert first.required_net_liters == 2000
    assert first.actual_parallels == 3

    capped = [
        StageConfig(grade=1, boost=False, success=Decimal("1.0"), target_liters=1000),
        StageConfig(grade=2, boost=False, success=Decimal("1.0"), target_liters=1000),
    ]
    first, second = calculate_results(capped, parallel_cap=2)
    assert first.actual_parallels == 2
    assert first.target_shortfall_liters == Decimal("0")
    assert second.actual_parallels == 0
    assert second.target_shortfall_liters == Decimal("1000")


def main() -> int:
    args = parse_args()

    if args.self_test:
        run_self_tests()
        print("Self-tests passed.")
        return 0

    try:
        stages = load_stages(Path(args.path))
        results = calculate_results(stages)
    except WaterCalcError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    print(render_table(results))
    limit_summary = render_limit_summary(results)
    if limit_summary:
        print()
        print(limit_summary)
    print()
    print(f"Per-stage parallel cap: {format_int(MAX_PARALLEL_CAP)}")
    print(f"Total source water required: {format_int(results[0].previous_grade_input)} L")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
