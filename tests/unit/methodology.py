#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
policy = json.loads((ROOT / "orchestration/skill-policy.json").read_text(encoding="utf-8"))
protocol = json.loads((ROOT / "orchestration/evaluation-protocol.json").read_text(encoding="utf-8"))

checks: list[tuple[bool, str]] = []

def check(condition: bool, message: str) -> None:
    checks.append((condition, message))
    print(("PASS" if condition else "FAIL") + " " + message)

check(policy["default_activation"] == "off", "skill injection nao e blanket por default")
check(policy["selection"]["mode"] == "evidence-gated", "selecao de skill exige evidencia")
check(policy["selection"]["require_version_compatibility"] is True, "compatibilidade de versao obrigatoria")
check(policy["selection"]["max_selected_skills_per_task"] == 1, "composicao multi-skill permanece desabilitada sem avaliacao")
required = set(policy["lifecycle"]["promotion_requires"])
check({"paired_evaluation", "deterministic_requirement_verifier", "negative_control", "context_interference_check"} <= required, "promocao cobre baseline, oraculo, controle e interferencia")
check(policy["claims"]["skill_is_not_certifier"] is True, "skill nao certifica a propria eficacia")

check(protocol["repository"]["fixed_commit_required"] is True, "snapshot fixo por tarefa")
check(protocol["requirement"]["acceptance_criteria_required"] is True, "criterios de aceitacao obrigatorios")
check(protocol["requirement"]["must_not_leak_skill_content"] is True, "requisito nao vaza conteudo da skill")
verifier = protocol["verifier"]
check(verifier["deterministic"] and verifier["execution_based"], "desfecho primario e deterministico e executado")
check(verifier["llm_as_judge_for_primary_outcome"] is False, "LLM-as-judge nao decide outcome primario")
check(verifier["keyword_only_checks_prohibited"] is True, "oraculo keyword-only proibido")
check(verifier["negative_control_required"] is True, "controle negativo obrigatorio")

design = protocol["design"]
check(design["paired_conditions"] == ["without_skill", "with_skill"], "contraste pareado explicito")
check(design["same_task_snapshot_between_conditions"] is True, "snapshot identico entre condicoes")
check(design["same_model_scaffold_between_paired_conditions"] is True, "modelo e scaffold controlados no par")
check(design["repeated_trials_required_for_stochastic_agents"] is True, "agentes estocasticos exigem repeticao")
check(design["skill_selection_evaluated_separately"] is True, "retrieval/selecao nao se confunde com utilidade")

metrics = protocol["metrics"]
check("paired_correctness_delta" in metrics["primary"], "delta pareado e metrica primaria")
check("token_cost" in metrics["secondary"] and "wall_clock_latency" in metrics["secondary"], "custo e latencia medidos")
check("context_interference_failures" in metrics["safety"], "interferencia contextual e desfecho de seguranca")
check("unnecessary_injection_rate" in metrics["selection"], "injecao desnecessaria e medida")

analysis = protocol["analysis"]
check(analysis["report_confidence_intervals"] is True, "incerteza estatistica reportada")
check(analysis["report_discordant_pairs"] is True, "pares discordantes reportados")
check(analysis["report_null_and_negative_results"] is True, "resultados nulos e negativos nao sao ocultados")
check(analysis["no_universal_skill_claim_from_single_model"] is True, "um modelo nao sustenta claim universal")
check(analysis["no_universal_scaffold_claim_from_single_scaffold"] is True, "um scaffold nao sustenta claim universal")

failed = sum(not ok for ok, _ in checks)
print(f"TOTAL={len(checks)} FAIL={failed}")
raise SystemExit(1 if failed else 0)
