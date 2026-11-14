package weights60

// Pass b reads the per-tree files of the first pass and writes them again, extended, to parts-60b:
//
//   - for every tree, StatHitRating and StatExpertiseRating a step below the baseline (weights[stat].below),
//     taken further down where the baseline sits over a hit cap, so the step lies wholly below it;
//   - for the tanks, threat, damage taken and TMI per stat, each run to its own interval
//     (weights[stat].tps, .dtps, .tmi), in place of the first pass's tank block.
//
// Every other value of the first pass is copied over unchanged.

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/core/simsignals"
	"github.com/wowsims/forever/sim/core/stats"
)

const (
	passBProbe        = 1000 // Iterations each side runs before the first sizing.
	passBTopUps       = 4    // Sizing passes after the probe.
	defaultBelowCap   = 600000
	defaultTankCap    = 300000
	defaultTankEpCi   = 0.05
	tankSetupFollowed = "sim/core/test_generators.go, defaultPlayerAndRaid: a config with IsTank names the player in raid.Tanks, and the suite's single target, core.NewDefaultTarget() of sim/core/test_utils.go (level 63, 2601 minimum base damage, 2.0 s swing, parry haste, crushing blows), attacks it. That is how sim/warrior/protection/protection_test.go, sim/paladin/protection/protection_test.go and sim/druid/feralbear/feralbear_test.go set up their tank. The player stands in front of the target and carries the UI's healing model, without which the engine counts no TMI. sim/druid/feralbear/ep_test.go, the engine's one tank stat weight test, uses a harder-hitting target of 6000 minimum base damage; it is not followed, so that the three tanks and the first pass share one fight."
)

func runPassB(t *testing.T, pkg string, trees []Tree, outDir string) {
	partsIn := filepath.Join(outDir, "parts")
	partsOut := filepath.Join(outDir, "parts-60b")
	if err := os.MkdirAll(partsOut, 0o755); err != nil {
		t.Fatal(err)
	}
	only := strings.ToLower(os.Getenv("W60_ONLY"))
	for _, tree := range trees {
		key := treeKey(tree)
		if only != "" && !strings.Contains(key, only) {
			continue
		}
		data, err := os.ReadFile(filepath.Join(partsIn, key+".json"))
		if err != nil {
			t.Fatalf("%s: the first pass's file is missing: %v", key, err)
		}
		start := time.Now()
		out, summary, err := passBTree(pkg, tree, data)
		if err != nil {
			t.Errorf("%s: %v", key, err)
			fmt.Printf("W60B %-22s FAILED %v\n", key, err)
			continue
		}
		if err := out.set("passBSeconds", round(time.Since(start).Seconds(), 1)); err != nil {
			t.Fatal(err)
		}
		written, err := json.MarshalIndent(out, "", "  ")
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(partsOut, key+".json"), written, 0o644); err != nil {
			t.Fatal(err)
		}
		fmt.Printf("W60B %-22s %s (%.0f s)\n", key, summary, time.Since(start).Seconds())
	}
}

func treeKey(tree Tree) string {
	return strings.ToLower(strings.ReplaceAll(tree.Class+"-"+tree.Tree, " ", "_"))
}

func unitStatName(u stats.UnitStat) string {
	if u.IsStat() {
		return proto.Stat(u.StatIdx()).String()
	}
	return proto.PseudoStat(u.PseudoStatIdx()).String()
}

// The attack kinds a tree's hit counts for: what its damage rolls against.
func hitChannels(tree Tree) []string {
	switch {
	case tree.Class == "Hunter":
		return []string{"ranged"}
	case tree.Class == "Mage", tree.Class == "Warlock", tree.Class == "Priest",
		tree.Class == "Shaman" && tree.Tree == "Elemental", tree.Class == "Druid" && tree.Tree == "Balance":
		return []string{"spell"}
	case tree.Class == "Paladin", tree.Class == "Shaman" && tree.Tree == "Enhancement":
		return []string{"melee", "spell"}
	default:
		return []string{"melee"}
	}
}

// The percents of the player's sheet a cap is compared with.
func sheetPercents(raid *proto.Raid, encounter *proto.Encounter) map[string]float64 {
	result := core.ComputeStats(&proto.ComputeStatsRequest{Raid: clone(raid), Encounter: clone(encounter)})
	final := result.GetRaidStats().GetParties()[0].Players[0].GetFinalStats()
	pseudo := func(s proto.PseudoStat) float64 {
		if int(s) < len(final.GetPseudoStats()) {
			return final.GetPseudoStats()[s]
		}
		return 0
	}
	spell := pseudo(proto.PseudoStat_PseudoStatSpellHitPercent)
	for _, school := range []proto.PseudoStat{
		proto.PseudoStat_PseudoStatSchoolHitPercentArcane, proto.PseudoStat_PseudoStatSchoolHitPercentFire,
		proto.PseudoStat_PseudoStatSchoolHitPercentFrost, proto.PseudoStat_PseudoStatSchoolHitPercentHoly,
		proto.PseudoStat_PseudoStatSchoolHitPercentNature, proto.PseudoStat_PseudoStatSchoolHitPercentShadow,
	} {
		spell = math.Max(spell, pseudo(school))
	}
	return map[string]float64{
		"melee":     round(pseudo(proto.PseudoStat_PseudoStatMeleeHitPercent), 3),
		"ranged":    round(pseudo(proto.PseudoStat_PseudoStatRangedHitPercent), 3),
		"spell":     round(spell, 3),
		"expertise": round(pseudo(proto.PseudoStat_PseudoStatExpertisePercent), 3),
	}
}

// The caps of the engine's attack table for the player against the first target, in percent: the miss of
// special attacks with the main hand (and the off hand when dual wielding, the lower of the two), of ranged
// attacks and of spells, which hit takes off; and the dodge, with the parry when the player stands in
// front, which expertise takes off.
func capsOf(request *proto.RaidSimRequest) (map[string]float64, error) {
	sim := core.NewSim(clone(request), simsignals.CreateSignals())
	character := sim.Raid.Parties[0].Players[0].GetCharacter()
	targets := character.Env.Encounter.AllTargetUnits
	if len(targets) == 0 {
		return nil, fmt.Errorf("the encounter has no target")
	}
	target := targets[0]
	table := character.AttackTables[target.UnitIndex]
	melee := table.MH.BaseMissChance
	if character.AutoAttacks.IsDualWielding {
		melee = math.Min(melee, table.OH.BaseMissChance)
	}
	expertise := target.PseudoStats.BaseDodgeChance + table.MH.BaseDodgeChance - character.PseudoStats.DodgeReduction
	if character.PseudoStats.InFrontOfTarget {
		expertise = math.Max(expertise, target.PseudoStats.BaseParryChance+table.MH.BaseParryChance)
	}
	return map[string]float64{
		"melee":     round(melee*100, 3),
		"ranged":    round(table.Ranged.BaseMissChance*100, 3),
		"spell":     round(table.BaseSpellMissChance*100, 3),
		"expertise": round(expertise*100, 3),
	}, nil
}

// A request with a stat moved by value on the player's bonus stats.
func withBonus(request *proto.RaidSimRequest, stat stats.UnitStat, value float64) *proto.RaidSimRequest {
	moved := clone(request)
	if value != 0 {
		stat.AddToStatsProto(moved.Raid.Parties[0].Players[0].BonusStats, value)
	}
	return moved
}

func passBTree(pkg string, tree Tree, oldData []byte) (*ordered, string, error) {
	seed := int64(envFloat("W60_SEED", defaultSeed))
	dpsEpCi := envFloat("W60_EPCI", defaultEpCi)
	tankEpCi := envFloat("W60B_TANK_EPCI", defaultTankEpCi)
	belowCap := int(envFloat("W60B_CAP_BELOW", defaultBelowCap))
	tankCap := int(envFloat("W60B_CAP_TANK", defaultTankCap))
	if tree.IterationCap > 0 {
		tankCap = int(tree.IterationCap)
		belowCap = min(belowCap, tankCap)
	}

	old, err := parseOrdered(oldData)
	if err != nil {
		return nil, "", err
	}
	baseline, err := old.object("baseline")
	if err != nil {
		return nil, "", err
	}
	var quality string
	_ = json.Unmarshal(baseline.get("quality"), &quality)
	if quality == "failed" {
		return old, "skipped: the first pass failed", nil
	}

	// The same request as the first pass, checked against what that pass recorded.
	swr := buildRequest(tree)
	gearless := clone(swr.Player)
	gearless.Rotation = nil
	var recordedPlayer any
	if err := json.Unmarshal(baseline.get("player"), &recordedPlayer); err != nil {
		return nil, "", err
	}
	if !reflect.DeepEqual(plain(gearless), recordedPlayer) {
		return nil, "", fmt.Errorf("the player differs from the first pass's")
	}
	var recordedRotation string
	_ = json.Unmarshal(baseline.get("rotationSha256"), &recordedRotation)
	if hashOf(swr.Player.Rotation) != recordedRotation {
		return nil, "", fmt.Errorf("the rotation differs from the first pass's")
	}

	hit := stats.UnitStatFromStat(stats.Stat(proto.Stat_StatHitRating))
	expertise := stats.UnitStatFromStat(stats.Stat(proto.Stat_StatExpertiseRating))
	armor := stats.UnitStatFromStat(stats.Stat(proto.Stat_StatArmor))
	reference := stats.UnitStatFromStat(stats.Stat(tree.Reference))
	if !tree.Tank {
		swr.StatsToWeigh = []proto.Stat{tree.Reference, proto.Stat_StatHitRating, proto.Stat_StatExpertiseRating}
		swr.PseudoStatsToWeigh = nil
	}
	swr.SimOptions = &proto.SimOptions{RandomSeed: seed, Iterations: 2}
	swr.Target = nil
	requests := core.StatWeightRequests(swr)
	base := newSeries("baseline", requests.BaseRequest, seed, true)

	measures := map[stats.UnitStat]*measure{}
	var order []stats.UnitStat
	for _, r := range requests.StatSimRequests {
		u := stats.UnitStatFromIdx(int(r.StatData.UnitStat))
		m := &measure{name: unitStatName(u)}
		if r.RequestLow != nil {
			m.sides = append(m.sides, &side{from: base, to: newSeries(m.name+" low", r.RequestLow, seed, false), mod: r.StatData.ModLow})
		}
		m.sides = append(m.sides, &side{from: base, to: newSeries(m.name+" high", r.RequestHigh, seed, false), mod: r.StatData.ModHigh})
		measures[u] = m
		order = append(order, u)
	}
	stepOf := func(u stats.UnitStat) float64 {
		for _, r := range requests.StatSimRequests {
			if int(r.StatData.UnitStat) == int(u) {
				return r.StatData.ModHigh
			}
		}
		return 0
	}
	refMeasure := measures[reference]
	if refMeasure == nil {
		return nil, "", fmt.Errorf("no requests for the reference stat")
	}
	armorMeasure := measures[armor]

	// The step below the baseline for hit and expertise.
	caps, err := capsOf(requests.BaseRequest)
	if err != nil {
		return nil, "", err
	}
	baseRaid, encounter := requests.BaseRequest.Raid, requests.BaseRequest.Encounter
	atBaseline := sheetPercents(baseRaid, encounter)
	type below struct {
		stat      stats.UnitStat
		channels  []string
		perStep   float64 // Percent one step moves.
		steps     int     // Steps between the baseline and the top of the measured step.
		measure   *measure
		upper     map[string]float64
		lower     map[string]float64
		stepValue float64
	}
	var belows []*below
	for _, b := range []*below{
		{stat: hit, channels: hitChannels(tree), perStep: stepOf(hit) / core.HitRatingPerHitPercent},
		{stat: expertise, channels: []string{"expertise"}, perStep: stepOf(expertise) / core.ExpertiseRatingPerExpertisePercent},
	} {
		b.stepValue = stepOf(b.stat)
		for _, channel := range b.channels {
			over := atBaseline[channel] - caps[channel]
			if over > 1e-9 {
				b.steps = max(b.steps, int(math.Ceil(over/b.perStep-1e-9)))
			}
		}
		if b.steps > 15 {
			return nil, "", fmt.Errorf("%s is %d steps over its cap", unitStatName(b.stat), b.steps)
		}
		upperRequest := withBonus(requests.BaseRequest, b.stat, -float64(b.steps)*b.stepValue)
		lowerRequest := withBonus(requests.BaseRequest, b.stat, -float64(b.steps+1)*b.stepValue)
		upper := base
		if b.steps > 0 {
			upper = newSeries(unitStatName(b.stat)+" upper", upperRequest, seed, true)
		}
		b.measure = &measure{name: unitStatName(b.stat) + " below", sides: []*side{{
			from: upper,
			to:   newSeries(unitStatName(b.stat)+" lower", lowerRequest, seed, false),
			mod:  -b.stepValue,
		}}}
		b.upper = sheetPercents(upperRequest.Raid, encounter)
		b.lower = sheetPercents(lowerRequest.Raid, encounter)
		belows = append(belows, b)
	}

	// What each measurement is run down to.
	var plans []*plan
	if tree.Tank {
		if armorMeasure == nil {
			return nil, "", fmt.Errorf("no requests for armor")
		}
		for _, u := range order {
			plans = append(plans, &plan{measure: measures[u], cap: tankCap, goals: []goal{
				{mTps, tankEpCi, refMeasure}, {mDtps, tankEpCi, armorMeasure}, {mTmi, tankEpCi, armorMeasure},
			}})
		}
		for _, p := range plans {
			if p.measure == refMeasure {
				p.goals = append(p.goals, goal{mDps, dpsEpCi, refMeasure})
			}
		}
	} else {
		plans = append(plans, &plan{measure: refMeasure, cap: belowCap, goals: []goal{{mDps, dpsEpCi, refMeasure}}})
	}
	for _, b := range belows {
		goals := []goal{{mDps, dpsEpCi, refMeasure}}
		if tree.Tank {
			goals = append(goals, goal{mTps, tankEpCi, refMeasure}, goal{mDtps, tankEpCi, armorMeasure}, goal{mTmi, tankEpCi, armorMeasure})
		}
		cap := belowCap
		if tree.Tank {
			cap = tankCap
		}
		plans = append(plans, &plan{measure: b.measure, cap: cap, goals: goals})
	}
	if err := runPlans(plans, passBProbe, passBTopUps, engineTargetShare); err != nil {
		return nil, "", err
	}

	// The file: the first pass's, extended.
	weights, err := old.object("weights")
	if err != nil {
		return nil, "", err
	}
	type worstOf struct {
		ci   float64
		stat string
	}
	worst := map[string]*worstOf{}
	note := func(metric string, ci float64, stat string) {
		if worst[metric] == nil || ci > worst[metric].ci {
			worst[metric] = &worstOf{ci, stat}
		}
	}
	var summary []string
	belowBlock := omap{}
	for _, b := range belows {
		name := unitStatName(b.stat)
		entry, err := weights.object(name)
		if err != nil {
			return nil, "", err
		}
		value, ci := b.measure.entry(mDps, refMeasure, "dps")
		note("dps", ci, name+" below")
		value = append(value,
			kv{"step", -b.stepValue},
			kv{"offset", -float64(b.steps) * b.stepValue},
			kv{"stepsBelowBaseline", b.steps},
		)
		if tree.Tank {
			for _, metric := range []int{mTps, mDtps, mTmi} {
				ref := refMeasure
				if metric != mTps {
					ref = armorMeasure
				}
				sub, subCi := b.measure.entry(metric, ref, "value")
				note(metricKeys[metric], subCi, name+" below")
				value = append(value, kv{metricKeys[metric], sub})
			}
		}
		if err := entry.set("below", value); err != nil {
			return nil, "", err
		}
		if err := weights.set(name, entry); err != nil {
			return nil, "", err
		}
		at := func(percents map[string]float64, keys []string) omap {
			out := omap{}
			for _, k := range keys {
				out = append(out, kv{k, percents[k]})
			}
			return out
		}
		belowBlock = append(belowBlock, kv{name, omap{
			{"channels", b.channels},
			{"capPercent", at(caps, b.channels)},
			{"baselinePercent", at(atBaseline, b.channels)},
			{"stepsBelowBaseline", b.steps},
			{"measuredFromPercent", at(b.upper, b.channels)},
			{"measuredToPercent", at(b.lower, b.channels)},
		}})
		var oldEp float64
		var oldEntry struct{ Ep float64 }
		_ = json.Unmarshal(weights.get(name), &oldEntry)
		oldEp = oldEntry.Ep
		newEp := 0.0
		if ref, _ := refMeasure.pooled(mDps).meanStdev(); ref != 0 {
			w, _ := b.measure.pooled(mDps).meanStdev()
			newEp = w / ref
		}
		short := strings.TrimPrefix(name, "Stat")
		summary = append(summary, fmt.Sprintf("%s %.2f->%.2f (down %d)", short, oldEp, newEp, b.steps))
	}
	refWeight, refStdev := refMeasure.pooled(mDps).meanStdev()
	belowBlock = append(belowBlock,
		kv{"reference", omap{
			{"stat", tree.Reference.String()},
			{"dps", refWeight},
			{"stdev", refStdev},
			{"n", refMeasure.pooled(mDps).n},
			{"note", "Measured again in this pass at the baseline, both sides, as the engine does; the below EPs divide by it."},
		}},
		kv{"rule", "The step runs from offset down by one step. Hit is stepped down from the baseline until the top of the step is at or below the cap of every attack kind in channels: the miss of special attacks (the lower of the two hands when dual wielding, without the dual-wield penalty of auto attacks), of ranged attacks, or of spells, from the engine's attack table against the target. Expertise is stepped the same way against the target's dodge, and its parry when the player stands in front."},
	)

	if tree.Tank {
		for _, u := range order {
			name := unitStatName(u)
			raw := weights.get(name)
			if raw == nil {
				continue
			}
			entry, err := parseOrdered(raw)
			if err != nil {
				return nil, "", err
			}
			for _, metric := range []int{mTps, mDtps, mTmi} {
				ref := refMeasure
				if metric != mTps {
					ref = armorMeasure
				}
				value, ci := measures[u].entry(metric, ref, "value")
				value = append(value, kv{"step", stepOf(u)}, kv{"bothSides", len(measures[u].sides) == 2})
				if ci > 0 {
					note(metricKeys[metric], ci, name)
				}
				if err := entry.set(metricKeys[metric], value); err != nil {
					return nil, "", err
				}
			}
			if err := weights.set(name, entry); err != nil {
				return nil, "", err
			}
		}
	}
	if err := old.set("weights", weights); err != nil {
		return nil, "", err
	}
	if err := old.set("belowCap", belowBlock); err != nil {
		return nil, "", err
	}

	if tree.Tank {
		old.remove("tank")
		refs := omap{}
		for _, metric := range []int{mTps, mDtps, mTmi} {
			m := refMeasure
			stat := tree.Reference.String()
			if metric != mTps {
				m, stat = armorMeasure, "StatArmor"
			}
			w, sd := m.pooled(metric).meanStdev()
			refs = append(refs, kv{metricKeys[metric], omap{{"stat", stat}, {"value", w}, {"stdev", sd}, {"n", m.pooled(metric).n}}})
		}
		met := omap{}
		worstBlock := omap{}
		for _, metric := range []string{"tps", "dtps", "tmi"} {
			if w := worst[metric]; w != nil {
				worstBlock = append(worstBlock, kv{metric, omap{{"epCi90", round(w.ci, 4)}, {"stat", w.stat}}})
				met = append(met, kv{metric, w.ci <= tankEpCi})
			}
		}
		stamina := measures[stats.UnitStatFromStat(stats.Stat(proto.Stat_StatStamina))]
		staminaTmi, _ := stamina.pooled(mTmi).meanStdev()
		raidTanks := len(requests.BaseRequest.Raid.Tanks) > 0
		if err := old.set("tankMetrics", omap{
			{"setupFollowed", tankSetupFollowed},
			{"playerIsTanking", raidTanks},
			{"healingModel", plain(requests.BaseRequest.Raid.Parties[0].Players[0].HealingModel)},
			{"references", refs},
			{"signs", "ep keeps the sign of weight over reference weight. Armor lowers damage taken and TMI, so a positive dtps or tmi ep lowers them as armor does, and a negative one raises them."},
			{"epCi90Target", tankEpCi},
			{"iterationCapPerSide", tankCap},
			{"worstEpCi90", worstBlock},
			{"met", met},
			{"tmiAccountsForHealth", omap{
				{"answer", staminaTmi != 0},
				{"staminaTmiPerPoint", staminaTmi},
				{"how", "The engine's TMI (sim/core/metrics_aggregator.go calculateTMI) weighs each hit taken as its damage over the tank's maximum health (sim/core/health.go RemoveHealth), sums those over 6 s windows (the healing model's burst window) and takes 10 ln(mean e^(10 x window sum)). Stamina raises maximum health, so it lowers TMI while it leaves damage taken alone. TMI is counted only for a tanking player with a healing model."},
			}},
		}); err != nil {
			return nil, "", err
		}
	}

	var simmed int64
	seen := map[*series]bool{}
	for _, p := range plans {
		for _, s := range p.measure.sides {
			for _, sr := range []*series{s.from, s.to} {
				if !seen[sr] {
					seen[sr] = true
					simmed += sr.iterations
				}
			}
		}
	}
	if err := old.set("passB", omap{
		{"seed", seed},
		{"probeIterationsPerSide", passBProbe},
		{"topUpPasses", passBTopUps},
		{"dpsEpCi90Target", dpsEpCi},
		{"tankEpCi90Target", tankEpCi},
		{"askedShareOfTarget", engineTargetShare},
		{"belowIterationCapPerSide", belowCap},
		{"iterationsSimmed", simmed},
	}); err != nil {
		return nil, "", err
	}
	text := strings.Join(summary, ", ")
	if tree.Tank {
		for _, metric := range []string{"tps", "dtps", "tmi"} {
			if w := worst[metric]; w != nil {
				text += fmt.Sprintf("; worst %s ±%.3f (%s)", metric, w.ci, strings.TrimPrefix(w.stat, "Stat"))
			}
		}
	}
	return old, text, nil
}
