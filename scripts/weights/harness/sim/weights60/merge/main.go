// Command merge joins the per-tree files weights60.Run wrote into one weights-60.json.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
)

type statInfo struct {
	Name  string `json:"name"`
	Index int    `json:"index"`
	Kind  string `json:"kind"` // "Stat" or "PseudoStat": which proto enum the name and index belong to.
	Unit  string `json:"unit"`
}

// What one unit of each stat is. A weight is the metric per one unit.
var units = map[string]string{
	"StatStrength":         "1 point of Strength",
	"StatAgility":          "1 point of Agility",
	"StatStamina":          "1 point of Stamina",
	"StatIntellect":        "1 point of Intellect",
	"StatHealingPower":     "1 point of bonus healing",
	"StatSpellDamage":      "1 point of bonus spell damage, every school",
	"StatArcaneDamage":     "1 point of bonus Arcane spell damage",
	"StatFireDamage":       "1 point of bonus Fire spell damage",
	"StatFrostDamage":      "1 point of bonus Frost spell damage",
	"StatHolyDamage":       "1 point of bonus Holy spell damage",
	"StatNatureDamage":     "1 point of bonus Nature spell damage",
	"StatShadowDamage":     "1 point of bonus Shadow spell damage",
	"StatSpellPiercing":    "1 point of spell penetration (target resistance ignored)",
	"StatSpirit":           "1 point of Spirit",
	"StatAttackPower":      "1 point of melee attack power",
	"StatRangedAttackPower": "1 point of ranged attack power",
	"StatFeralAttackPower": "1 point of attack power in Cat and Bear form only",
	"StatHitRating":        fmt.Sprintf("1 rating point; %g rating = 1%% hit, melee, ranged and spell alike", core.HitRatingPerHitPercent),
	"StatCritRating":       fmt.Sprintf("1 rating point; %g rating = 1%% crit, melee, ranged and spell alike", core.CritRatingPerCritPercent),
	"StatHasteRating":      fmt.Sprintf("1 rating point; %g rating = 1%% haste, melee, ranged and spell alike", core.HasteRatingPerHastePercent),
	"StatArmorPenetration": "1 point of target armor ignored",
	"StatExpertiseRating":  fmt.Sprintf("1 rating point; %g rating = 1%% less dodge and parry by the target", core.ExpertiseRatingPerExpertisePercent),
	"StatDefenseRating":    fmt.Sprintf("1 rating point; %g rating = 1 Defense skill", core.DefenseRatingPerDefenseLevel),
	"StatBlockRating":      fmt.Sprintf("1 rating point; %g rating = 1%% block", core.BlockRatingPerBlockPercent),
	"StatBlockValue":       "1 point of damage blocked per block",
	"StatDodgeRating":      fmt.Sprintf("1 rating point; %g rating = 1%% dodge", core.DodgeRatingPerDodgePercent),
	"StatParryRating":      fmt.Sprintf("1 rating point; %g rating = 1%% parry", core.ParryRatingPerParryPercent),
	"StatArmor":            "1 point of armor on an item, which the armor multipliers scale",
	"StatBonusArmor":       "1 point of bonus (green) armor",
	"StatHealth":           "1 point of health",
	"StatMana":             "1 point of mana",
	"StatMP5":              "1 mana per 5 seconds",
	"StatArcaneResistance": "1 point of Arcane resistance",
	"StatFireResistance":   "1 point of Fire resistance",
	"StatFrostResistance":  "1 point of Frost resistance",
	"StatNatureResistance": "1 point of Nature resistance",
	"StatShadowResistance": "1 point of Shadow resistance",
	"StatPhysicalDamage":   "1 point of flat damage added to each physical hit",
	"StatArmorNoMods":      "1 point of armor that no armor multiplier scales",

	"PseudoStatMainHandDps": "1 damage per second of the main hand weapon",
	"PseudoStatOffHandDps":  "1 damage per second of the off hand weapon",
	"PseudoStatRangedDps":   "1 damage per second of the ranged weapon",
}

func main() {
	parts := flag.String("parts", "", "the folder of per-tree files")
	out := flag.String("out", "", "the file to write")
	repo := flag.String("repo", "https://github.com/wowsims/forever", "the engine's repository")
	commit := flag.String("commit", "", "the engine commit simmed")
	commitDate := flag.String("commitDate", "", "that commit's date")
	variant := flag.String("variant", "", "b for the second pass's file")
	flag.Parse()

	files, err := filepath.Glob(filepath.Join(*parts, "*.json"))
	if err != nil || len(files) == 0 {
		fmt.Fprintln(os.Stderr, "no per-tree files in", *parts)
		os.Exit(1)
	}
	type tree struct {
		key  string
		data json.RawMessage
	}
	var trees []tree
	for _, file := range files {
		data, err := os.ReadFile(file)
		if err != nil {
			panic(err)
		}
		var head struct{ Class, Tree string }
		if err := json.Unmarshal(data, &head); err != nil {
			panic(fmt.Sprintf("%s: %v", file, err))
		}
		trees = append(trees, tree{head.Class + "/" + head.Tree, data})
	}
	sort.Slice(trees, func(i, j int) bool { return trees[i].key < trees[j].key })

	var stats []statInfo
	for i := 0; i < len(proto.Stat_name); i++ {
		name := proto.Stat(i).String()
		stats = append(stats, statInfo{name, i, "Stat", units[name]})
	}
	for _, s := range []proto.PseudoStat{proto.PseudoStat_PseudoStatMainHandDps, proto.PseudoStat_PseudoStatOffHandDps, proto.PseudoStat_PseudoStatRangedDps} {
		stats = append(stats, statInfo{s.String(), int(s), "PseudoStat", units[s.String()]})
	}

	output := struct {
		Engine struct {
			Repo       string `json:"repo"`
			Commit     string `json:"commit"`
			CommitDate string `json:"commitDate"`
		} `json:"engine"`
		RanAt  string `json:"ranAt"`
		Method struct {
			Level         int      `json:"level"`
			Weights       string   `json:"weights"`
			Ep            string   `json:"ep"`
			Interval      string   `json:"interval"`
			Fight         string   `json:"fight"`
			ProbePairs    int      `json:"probePairs"`
			MaxTopUps     int      `json:"maxTopUpPasses"`
			Z90           float64  `json:"z90"`
			Notes         []string `json:"notes"`
		} `json:"method"`
		Stats []statInfo        `json:"stats"`
		Trees []json.RawMessage `json:"trees"`
	}{}
	output.Engine.Repo, output.Engine.Commit, output.Engine.CommitDate = *repo, *commit, *commitDate
	output.RanAt = time.Now().UTC().Format(time.RFC3339)
	output.Method.Level = core.CharacterLevel
	output.Method.Weights = "core.StatWeights of the engine: the metric per one unit of the stat, the mean of paired differences against the baseline at the same seeds, from a run above the baseline and, except for hit and expertise, one below it. step is the size of that run."
	output.Method.Ep = "ep is the weight divided by the weight of the tree's reference stat, with its sign kept: a negative ep is a stat that moves the metric against the reference stat. In tank.dtps and tank.tmi it divides by the weight of StatArmor, so a positive ep there lowers damage taken as armor does. The engine's own EP values are absolute and are not used."
	output.Method.Interval = "stdev is the standard deviation of the paired differences and n their count; ci90 = z90 * stdev / sqrt(n), and epCi90 the same for ep. The engine adds iterations to a stat until epCi90 is at or under precision.epCi90Target or its top-up passes run out."
	output.Method.Fight = "Every tree sims the Go test suites' default fight: full raid, party and individual buffs, full debuffs, one level 63 target, 180 s. Each tree records the values under baseline.buffs and baseline.encounter."
	output.Method.ProbePairs = core.StatWeightTargetProbeIterations
	output.Method.MaxTopUps = core.StatWeightMaxTopUpPasses
	output.Method.Z90 = core.StatWeightZ90
	output.Method.Notes = []string{
		"identicalToBaseline marks a stat whose every probe iteration matched the baseline exactly: a measured 0. The engine returns no sample count for it, so n is the probe's pairs.",
		"A weight of 0 for StatHitRating or StatExpertiseRating can also mean the baseline is at the cap.",
		"The gear of every baseline is in baseline.player.equipment as the item and enchant ids simmed.",
	}
	if *variant == "b" {
		output.Method.Notes = append(output.Method.Notes,
			"This file is weights-60.json with two additions from a second pass (each tree's passB block), every other value copied over unchanged.",
			"weights.StatHitRating.below and weights.StatExpertiseRating.below: the weight of one step down from offset (a rating below the baseline, 0 for the baseline itself), paired with the run at offset as the engine pairs its runs, and run to the same interval. offset is below 0 where the baseline sits over a hit cap: the tree's belowCap block names the attack kinds, their caps and the hit at both ends of the step. The ep divides by the reference stat's weight measured again in the same pass (belowCap.reference).",
			"Tank trees: weights[stat].tps, .dtps and .tmi, each with its own n and interval. tps divides by the reference stat's threat weight, dtps and tmi by StatArmor's, with the sign kept. The tankMetrics block gives the setup, the references, the worst intervals and the iteration cap, and replaces the first pass's tank block. Their weights[stat].dps stays the first pass's.",
		)
	}
	output.Stats = stats
	for _, t := range trees {
		output.Trees = append(output.Trees, t.data)
	}

	data, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		panic(err)
	}
	if err := os.WriteFile(*out, append(data, '\n'), 0o644); err != nil {
		panic(err)
	}
	fmt.Printf("wrote %s: %d trees\n", *out, len(trees))
}
