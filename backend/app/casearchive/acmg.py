"""ACMG criteria handling for the case archive.

The evidence levels and the combination rules mirror the ones already used by
the REEV frontend (``frontend/src/lib/acmgSeqvar.ts``) so that a classification
computed on the server and one computed in the browser cannot disagree.  The
criteria themselves are *not* re-implemented here: they come from the ACMG
service that REEV already ships with (auto-acmg, with WinterVar as fallback),
reached through ``app.api.internal.endpoints.remote``.
"""

#: All criteria considered by REEV, in display order.
ACMG_CRITERIA: tuple[str, ...] = (
    "pvs1",
    "ps1",
    "ps2",
    "ps3",
    "ps4",
    "pm1",
    "pm2",
    "pm3",
    "pm4",
    "pm5",
    "pm6",
    "pp1",
    "pp2",
    "pp3",
    "pp4",
    "ba1",
    "bs1",
    "bs2",
    "bs3",
    "bs4",
    "bp1",
    "bp2",
    "bp3",
    "bp4",
    "bp5",
    "bp7",
)

CONFLICTING = "Conflicting"
PATHOGENIC = "Pathogenic"
LIKELY_PATHOGENIC = "Likely pathogenic"
UNCERTAIN = "Uncertain significance"
LIKELY_BENIGN = "Likely benign"
BENIGN = "Benign"

#: Rank used to decide whether a change is an improvement or a regression.
CLASS_RANK: dict[str, int] = {
    BENIGN: 0,
    LIKELY_BENIGN: 1,
    UNCERTAIN: 2,
    CONFLICTING: 2,
    LIKELY_PATHOGENIC: 3,
    PATHOGENIC: 4,
}


def evidence_levels(criteria: dict[str, bool]) -> dict[str, int]:
    """Count the criteria present per ACMG evidence level."""
    levels = {"very_strong": 0, "strong_path": 0, "moderate": 0, "supporting_path": 0}
    levels_benign = {"standalone": 0, "strong_benign": 0, "supporting_benign": 0}

    very_strong = {"pvs1"}
    strong_path = {"ps1", "ps2", "ps3", "ps4"}
    moderate = {"pm1", "pm2", "pm3", "pm4", "pm5", "pm6"}
    supporting_path = {"pp1", "pp2", "pp3", "pp4"}
    standalone = {"ba1"}
    strong_benign = {"bs1", "bs2", "bs3", "bs4"}
    supporting_benign = {"bp1", "bp2", "bp3", "bp4", "bp5", "bp7"}

    for key, present in criteria.items():
        if not present:
            continue
        key = key.lower()
        if key in very_strong:
            levels["very_strong"] += 1
        elif key in strong_path:
            levels["strong_path"] += 1
        elif key in moderate:
            levels["moderate"] += 1
        elif key in supporting_path:
            levels["supporting_path"] += 1
        elif key in standalone:
            levels_benign["standalone"] += 1
        elif key in strong_benign:
            levels_benign["strong_benign"] += 1
        elif key in supporting_benign:
            levels_benign["supporting_benign"] += 1

    levels.update(levels_benign)  # type: ignore[arg-type]
    return levels


def classify(criteria: dict[str, bool]) -> tuple[str, bool]:
    """Turn a set of ACMG criteria into REEV's classification.

    This is a line-by-line port of ``AcmgSeqvarState.getAcmgClass()`` in
    ``frontend/src/lib/acmgSeqvar.ts``: the same evidence levels per criterion,
    the same combination rules and the same ``Conflicting`` tier, so that the
    server and the browser cannot report different classes for the same
    criteria set.

    Returns the class and whether it is conflicting.
    """
    lv = evidence_levels(criteria)
    pvs = lv["very_strong"]
    ps = lv["strong_path"]
    pm = lv["moderate"]
    pp = lv["supporting_path"]
    ba = lv["standalone"]
    bs = lv["strong_benign"]
    bp = lv["supporting_benign"]

    is_pathogenic = (
        (pvs == 1 and (ps >= 1 or pm >= 2 or (pm == 1 and pp == 1) or pp >= 2))
        or ps >= 2
        or (ps == 1 and (pm >= 3 or (pm == 2 and pp >= 2) or (pm == 1 and pp >= 4)))
    )
    is_likely_pathogenic = (
        (pvs == 1 and pm == 1)
        or (ps == 1 and 1 <= pm <= 2)
        or (ps == 1 and pp >= 2)
        or pm >= 3
        or (pm == 2 and pp >= 2)
        or (pm == 1 and pp >= 4)
    )
    is_benign = ba > 0 or bs >= 2
    is_likely_benign = (bs == 1 and bp == 1) or bp >= 2
    conflicting = (is_pathogenic or is_likely_pathogenic) and (is_benign or is_likely_benign)

    if conflicting:
        return CONFLICTING, True
    if is_pathogenic:
        return PATHOGENIC, False
    if is_likely_pathogenic:
        return LIKELY_PATHOGENIC, False
    if is_benign:
        return BENIGN, False
    if is_likely_benign:
        return LIKELY_BENIGN, False
    return UNCERTAIN, False


def is_conflicting(criteria: dict[str, bool]) -> bool:
    """Whether pathogenic and benign criteria are both present."""
    has_path = any(criteria.get(k) for k in ("pvs1", "ps1", "ps2", "ps3", "ps4", "pm1", "pm3",
                                            "pm4", "pm5", "pm6", "pp1", "pp2", "pp3", "pp4"))
    has_benign = any(criteria.get(k) for k in ("ba1", "bs1", "bs2", "bs3", "bs4", "bp1", "bp2",
                                              "bp3", "bp4", "bp5", "bp7"))
    return bool(has_path and has_benign)


def severity_for(old_class: str | None, new_class: str) -> str:
    """Severity of a class change, seen from a diagnostic point of view."""
    old_rank = CLASS_RANK.get(old_class or UNCERTAIN, 2)
    new_rank = CLASS_RANK.get(new_class, 2)
    if new_rank > old_rank:
        return "critical" if new_rank >= 3 else "warning"
    if new_rank < old_rank:
        return "warning" if new_rank >= 2 else "info"
    return "info"
