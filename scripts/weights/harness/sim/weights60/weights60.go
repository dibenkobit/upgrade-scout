// Package weights60 computes level 60 stat weights for one talent tree at a time, through the engine's own
// core.StatWeights, and writes one JSON file per tree. It is not part of wowsims/forever: weights/run.sh copies
// it into a checkout of the pinned commit, next to one weights60_test.go per spec package, because the suite
// configs and default options of each spec live in that package's test files.
//
// The baseline of a tree is the repo's own preset for it: the player comes from the UI's preset build (a SIML
// build over the spec's defaults.siml, a build.json) or from the spec's Go test suite with the UI build's gear,
// talents and rotation. The fight is the same for every tree and is the Go test suites' default: full raid,
// party and individual buffs, full debuffs, one level 63 target, 180 s.
package weights60

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/siml"
	"google.golang.org/protobuf/encoding/protojson"
	googleProto "google.golang.org/protobuf/proto"
)

const (
	baselineIterations = 5000
	defaultEpCi        = 0.03
	engineTargetShare  = 0.9
	defaultSeed        = 60
	fightSource        = "the repo's Go test suite default: core.FullRaidBuffs, core.FullPartyBuffs, core.FullIndividualBuffs, core.FullDebuffs and core.MakeSingleTargetEncounter(0) (sim/core/test_utils.go)"
)

// What the baseline was built from, by name. The exact values simmed are written next to it.
type Baseline struct {
	Gear           string
	Talents        string
	Rotation       string
	Consumables    string
	Quality        string // "preset" or "testing"; a tree that does not sim is written as "failed".
	Note           string
	GearSharedWith []string // Other trees of this file that sim on the same gear set.
}

type Tree struct {
	Class     string
	Tree      string
	SimStatus string     // The launch status the UI gives the sim: Alpha, Unlaunched.
	Reference proto.Stat // The stat EP divides by, the UI's epReferenceStat of the spec.
	Tank      bool

	// One of the two. Config is a Go test suite config; Player is a whole player from a UI build file, which is
	// simmed with the suite default fight and individual buffs.
	Config *core.CharacterSuiteConfig
	Player *proto.Player

	// The most iterations a stat's run above or below the baseline may take, for a sim too slow to run every
	// stat down to the interval wanted; 0 is no cap. A capped tree says so under precision.
	IterationCap int32

	Baseline Baseline
}

// A gear set of ui/specs, which must exist and hold items.
func Gear(dir, name string) core.GearSetCombo {
	combo := core.GetGearSet(dir, name)
	if combo.GearSet == nil || len(combo.GearSet.Items) == 0 {
		panic(fmt.Sprintf("gear set %s/%s is missing or empty", dir, name))
	}
	return combo
}

// An APL of ui/specs, which must exist and hold rows.
func APL(dir, name string) core.RotationCombo {
	combo := core.GetAplRotation(dir, name)
	if combo.Rotation == nil || len(combo.Rotation.PriorityList) == 0 {
		panic(fmt.Sprintf("APL %s/%s is missing or has no rows", dir, name))
	}
	return combo
}

// The player of a SIML setup as the site loads it: the spec's defaults.siml, and over it a preset build when
// buildPath names one.
func SimlPlayer(defaultsPath, buildPath string) *proto.Player {
	settings := googleProto.Clone(readSiml(defaultsPath).Settings).(*proto.IndividualSimSettings)
	if buildPath != "" {
		siml.LoadBuild(settings, readSiml(buildPath).Settings)
	}
	if settings.Player == nil {
		panic(fmt.Sprintf("%s holds no player", defaultsPath))
	}
	return settings.Player
}

func readSiml(path string) *siml.File {
	f, err := siml.ReadFile(path)
	if err != nil {
		panic(fmt.Sprintf("%s: %v", path, err))
	}
	return f
}

// The player of a build.json, the settings the UI exports.
func JSONBuildPlayer(path string) *proto.Player {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	settings := &proto.IndividualSimSettings{}
	if err := protojson.Unmarshal(data, settings); err != nil {
		panic(fmt.Sprintf("%s: %v", path, err))
	}
	if settings.Player == nil {
		panic(fmt.Sprintf("%s holds no player", path))
	}
	return settings.Player
}

// Runs each tree and writes $W60_OUT/parts/<class>-<tree>.json. Skipped unless W60_OUT is set, so the files do
// nothing in an ordinary test run.
func Run(t *testing.T, pkg string, trees []Tree) {
	outDir := os.Getenv("W60_OUT")
	if outDir == "" {
		t.Skip("W60_OUT is not set; weights/run.sh sets it")
	}
	if os.Getenv("W60_PASS") == "b" {
		runPassB(t, pkg, trees, outDir)
		return
	}
	if err := os.MkdirAll(filepath.Join(outDir, "parts"), 0o755); err != nil {
		t.Fatal(err)
	}
	only := strings.ToLower(os.Getenv("W60_ONLY"))
	for _, tree := range trees {
		key := strings.ToLower(strings.ReplaceAll(tree.Class+"-"+tree.Tree, " ", "_"))
		if only != "" && !strings.Contains(key, only) {
			continue
		}
		start := time.Now()
		part := runTree(pkg, tree)
		part = append(part, kv{"seconds", round(time.Since(start).Seconds(), 1)})
		data, err := json.MarshalIndent(part, "", "  ")
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(outDir, "parts", key+".json"), data, 0o644); err != nil {
			t.Fatal(err)
		}
		fmt.Printf("W60 %-22s %s\n", key, summary(part))
	}
}

func envFloat(name string, fallback float64) float64 {
	if v := os.Getenv(name); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			return f
		}
	}
	return fallback
}

func clone[M googleProto.Message](m M) M { return googleProto.Clone(m).(M) }

// The stat weights request of the tree, without sim options: the player, the suite default fight, and every
// stat of the Stat enum with the three weapon DPS pseudo stats to weigh.
func buildRequest(tree Tree) *proto.StatWeightsRequest {
	var swr *proto.StatWeightsRequest
	switch {
	case tree.Player != nil:
		player := clone(tree.Player)
		player.Buffs = clone(core.FullIndividualBuffs)
		if tree.Tank {
			player.Buffs = clone(core.FullTankIndividualBuffs)
		}
		swr = &proto.StatWeightsRequest{
			Player:     player,
			RaidBuffs:  clone(core.FullRaidBuffs),
			PartyBuffs: clone(core.FullPartyBuffs),
			Debuffs:    clone(core.FullDebuffs),
			Encounter:  clone(core.MakeSingleTargetEncounter(0)),
		}
		if tree.Tank {
			swr.Tanks = []*proto.UnitReference{{Type: proto.UnitReference_Player, Index: 0}}
		}
	case tree.Config != nil:
		config := *tree.Config
		config.IsTank = config.IsTank || tree.Tank
		config.StatsToWeigh = []proto.Stat{tree.Reference}
		config.EPReferenceStat = tree.Reference
		for _, generator := range core.FullCharacterTestSuiteGenerator([]core.CharacterSuiteConfig{config}) {
			for i := 0; i < generator.NumTests() && swr == nil; i++ {
				if _, _, request, _ := generator.GetTest(i); request != nil {
					swr = clone(request)
				}
			}
		}
		if swr == nil {
			panic("the suite generated no stat weights request")
		}
	default:
		panic("a tree needs a Config or a Player")
	}

	swr.SimOptions = nil
	swr.StatsToWeigh = nil
	for i := 0; i < len(proto.Stat_name); i++ {
		swr.StatsToWeigh = append(swr.StatsToWeigh, proto.Stat(i))
	}
	swr.PseudoStatsToWeigh = []proto.PseudoStat{
		proto.PseudoStat_PseudoStatMainHandDps,
		proto.PseudoStat_PseudoStatOffHandDps,
		proto.PseudoStat_PseudoStatRangedDps,
	}
	swr.EpReferenceStat = tree.Reference
	swr.HpsReferenceStat = tree.Reference
	return swr
}

func runTree(pkg string, tree Tree) (part omap) {
	seed := int64(envFloat("W60_SEED", defaultSeed))
	epCi := envFloat("W60_EPCI", defaultEpCi)

	head := omap{
		{"class", tree.Class},
		{"tree", tree.Tree},
		{"sim", pkg},
		{"simStatus", tree.SimStatus},
	}
	baseline := omap{
		{"gear", tree.Baseline.Gear},
		{"talents", tree.Baseline.Talents},
		{"rotation", tree.Baseline.Rotation},
		{"consumables", tree.Baseline.Consumables},
	}
	fail := func(reason string) omap {
		baseline = append(baseline, kv{"quality", "failed"}, kv{"note", strings.TrimSpace(reason + " " + tree.Baseline.Note)})
		return append(head, kv{"baseline", baseline}, kv{"reference", tree.Reference.String()}, kv{"weights", omap{}})
	}
	defer func() {
		if r := recover(); r != nil {
			part = fail(fmt.Sprintf("The harness panicked: %v.", r))
		}
	}()

	swr := buildRequest(tree)
	player := swr.Player

	// What was simmed, exactly.
	gearless := clone(player)
	gearless.Rotation = nil
	rotationRows := 0
	rotationHash := ""
	if player.Rotation != nil {
		rotationRows = len(player.Rotation.PriorityList)
		rotationHash = hashOf(player.Rotation)
	}
	targets := swr.Encounter.GetTargets()
	levels := []int32{}
	for _, target := range targets {
		levels = append(levels, target.Level)
	}
	baseline = append(baseline,
		kv{"talentsString", player.TalentsString},
		kv{"rotationRows", rotationRows},
		kv{"rotationSha256", rotationHash},
		kv{"buffs", omap{
			{"source", fightSource},
			{"raid", plain(swr.RaidBuffs)},
			{"party", plain(swr.PartyBuffs)},
			{"individual", plain(player.Buffs)},
			{"debuffs", plain(swr.Debuffs)},
		}},
		kv{"encounter", omap{
			{"source", fightSource},
			{"durationSeconds", swr.Encounter.GetDuration()},
			{"durationVariationSeconds", swr.Encounter.GetDurationVariation()},
			{"targets", len(targets)},
			{"targetLevels", levels},
			{"playerIsTanking", len(swr.Tanks) > 0},
			{"proto", plain(swr.Encounter)},
		}},
		kv{"player", plain(gearless)},
	)
	if len(tree.Baseline.GearSharedWith) > 0 {
		baseline = append(baseline, kv{"gearSharedWith", tree.Baseline.GearSharedWith})
	}

	if rotationRows == 0 {
		return fail("The rotation holds no APL row, so the sim would cast nothing.")
	}

	// The baseline on its own, to see that the tree sims at all and what it casts.
	raid := core.SinglePlayerRaidProto(clone(player), clone(swr.PartyBuffs), clone(swr.RaidBuffs), clone(swr.Debuffs))
	raid.Tanks = swr.Tanks
	base := core.RunRaidSimConcurrent(&proto.RaidSimRequest{
		Raid:       raid,
		Encounter:  clone(swr.Encounter),
		SimOptions: &proto.SimOptions{Iterations: baselineIterations, RandomSeed: seed},
	})
	if base.Error != nil {
		return fail("The baseline sim failed: " + firstLine(base.Error.Message) + ".")
	}
	metrics := base.RaidMetrics.Parties[0].Players[0]
	actions, casting := topActions(metrics)
	head = append(head,
		kv{"dps", round(metrics.Dps.Avg, 1)},
		kv{"dpsStdev", round(metrics.Dps.Stdev, 1)},
		kv{"baselineIterations", baselineIterations},
		kv{"topActions", actions},
		kv{"sheet", sheet(raid, swr.Encounter)},
	)
	if tree.Tank {
		head = append(head, kv{"tankBaseline", omap{
			{"tps", round(metrics.Threat.Avg, 1)},
			{"dtps", round(metrics.Dtps.Avg, 1)},
			{"tmi", round(metrics.Tmi.Avg, 1)},
			{"chanceOfDeath", round(metrics.ChanceOfDeath, 4)},
		}})
	}
	if !(metrics.Dps.Avg > 0) {
		return fail("The baseline does 0 DPS.")
	}
	if casting == 0 {
		return fail("The baseline casts nothing but automatic attacks.")
	}

	// The weights. With a target the engine runs a probe of core.StatWeightTargetProbeIterations and then up to
	// core.StatWeightMaxTopUpPasses more passes on the stats still above the target.
	swr.SimOptions = &proto.SimOptions{RandomSeed: seed}
	targetMetrics := []proto.StatWeightsTargetMetric{proto.StatWeightsTargetMetric_StatWeightsTargetMetricDps}
	if tree.Tank {
		targetMetrics = append(targetMetrics, proto.StatWeightsTargetMetric_StatWeightsTargetMetricTps)
	}
	// The engine sizes each top-up from the stdev seen so far and stops after its last pass, so a stat can end a
	// little above what it was asked for: it is asked for slightly less than the interval wanted.
	swr.Target = &proto.StatWeightsTarget{EpCi: epCi * engineTargetShare, Metrics: targetMetrics}
	if tree.IterationCap > 0 {
		swr.Target.MaxIterationMultiplier = max(1, tree.IterationCap/(core.StatWeightTargetProbeIterations/2))
	}
	result := core.StatWeights(swr)
	if result.Error != nil {
		return fail("The stat weights run failed: " + firstLine(result.Error.Message) + ".")
	}

	type unit struct {
		name   string
		pseudo bool
		index  int
	}
	var units []unit
	for _, s := range swr.StatsToWeigh {
		units = append(units, unit{s.String(), false, int(s)})
	}
	for _, s := range swr.PseudoStatsToWeigh {
		units = append(units, unit{s.String(), true, int(s)})
	}
	get := func(values *proto.UnitStats, u unit) float64 {
		list := values.GetStats()
		if u.pseudo {
			list = values.GetPseudoStats()
		}
		if u.index >= len(list) {
			return 0
		}
		return list[u.index]
	}

	probePairs := float64(core.StatWeightTargetProbeIterations)
	weights := omap{}
	tank := map[string]omap{"tps": {}, "dtps": {}, "tmi": {}, "pDeath": {}}
	maxN, worst, worstStat := 0.0, 0.0, ""
	for _, u := range units {
		n := get(result.SampleCounts, u)
		w := get(result.Dps.Weights, u)
		// A stat whose every run matched the baseline iteration for iteration is skipped by the engine and comes
		// back with no sample count: its weight is a measured 0 over the probe pass.
		identical := n == 0
		if identical {
			n = probePairs
			if get(result.StepBelow, u) == 0 {
				n = probePairs / 2
			}
		}
		maxN = math.Max(maxN, n)
		entry := metricEntry("dps", result.Dps, u.pseudo, u.index, n, tree.Reference)
		entry = append(entry,
			kv{"step", get(result.StepAbove, u)},
			kv{"bothSides", get(result.StepBelow, u) != 0},
		)
		if identical {
			entry = append(entry, kv{"identicalToBaseline", true})
		}
		weights = append(weights, kv{u.name, entry})

		checked := []*proto.StatWeightValues{result.Dps}
		if tree.Tank {
			checked = append(checked, result.Tps)
			armor := proto.Stat_StatArmor // core.DTPSReferenceStat
			tank["tps"] = append(tank["tps"], kv{u.name, metricEntry("tps", result.Tps, u.pseudo, u.index, n, tree.Reference)})
			tank["dtps"] = append(tank["dtps"], kv{u.name, metricEntry("dtps", result.Dtps, u.pseudo, u.index, n, armor)})
			tank["tmi"] = append(tank["tmi"], kv{u.name, metricEntry("tmi", result.Tmi, u.pseudo, u.index, n, armor)})
			// The chance to die has no paired samples: it is the difference of two runs' death rates.
			tank["pDeath"] = append(tank["pDeath"], kv{u.name, omap{{"pDeath", get(result.PDeath.Weights, u)}}})
		}
		if w != 0 {
			for _, values := range checked {
				if ci := core.StatWeightZ90 * get(values.EpValuesStdev, u) / math.Sqrt(n); ci > worst {
					worst, worstStat = ci, u.name
				}
			}
		}
	}

	quality := tree.Baseline.Quality
	baseline = append(baseline, kv{"quality", quality}, kv{"note", tree.Baseline.Note})
	part = append(head,
		kv{"baseline", baseline},
		kv{"reference", tree.Reference.String()},
		kv{"iterations", int(maxN)},
		kv{"precision", omap{
			{"epCi90Target", epCi},
			{"epCi90AskedOfEngine", round(epCi*engineTargetShare, 4)},
			{"worstEpCi90", round(worst, 4)},
			{"worstStat", worstStat},
			{"met", worst <= epCi},
			{"iterationCapPerSide", tree.IterationCap},
			{"targetedMetrics", metricNames(targetMetrics)},
		}},
		kv{"weights", weights},
	)
	if tree.Tank {
		part = append(part, kv{"tank", omap{
			{"dtpsReference", "StatArmor"}, // core.DTPSReferenceStat, which dtps, tmi and pDeath EP divide by.
			{"tps", tank["tps"]},
			{"dtps", tank["dtps"]},
			{"tmi", tank["tmi"]},
			{"pDeath", tank["pDeath"]},
		}})
	}
	return part
}

// One stat's weight in one metric: the metric per point, the stdev of the paired differences behind it, their
// count, the EP against the reference stat, and the 90% intervals of both (1.645 * stdev / sqrt(n)).
//
// The EP is the weight over the reference stat's weight with its sign kept: positive moves the metric the way
// the reference stat does. The engine's own EP values are absolute, which shows a stat that lowers DPS as a
// gain, so they are not used.
func metricEntry(name string, values *proto.StatWeightValues, pseudo bool, index int, n float64, reference proto.Stat) omap {
	get := func(v *proto.UnitStats) float64 {
		list := v.GetStats()
		if pseudo {
			list = v.GetPseudoStats()
		}
		if index >= len(list) {
			return 0
		}
		return list[index]
	}
	weight, stdev, ep, epCi := get(values.Weights), get(values.WeightsStdev), 0.0, 0.0
	if stats := values.Weights.GetStats(); int(reference) < len(stats) && stats[reference] != 0 {
		ep = weight / stats[reference]
		epCi = core.StatWeightZ90 * stdev / math.Abs(stats[reference]) / math.Sqrt(n)
	}
	return omap{
		{name, weight},
		{"stdev", stdev},
		{"n", int(n)},
		{"ep", ep},
		{"ci90", core.StatWeightZ90 * stdev / math.Sqrt(n)},
		{"epCi90", epCi},
	}
}

// The baseline's character sheet with gear, talents, buffs and consumables: every stat and pseudo stat that is
// not 0. It shows where the baseline stands against a cap, which is what a weight near 0 for hit or expertise
// usually means.
func sheet(raid *proto.Raid, encounter *proto.Encounter) omap {
	out := omap{}
	result := core.ComputeStats(&proto.ComputeStatsRequest{Raid: clone(raid), Encounter: clone(encounter)})
	parties := result.GetRaidStats().GetParties()
	if len(parties) == 0 || len(parties[0].Players) == 0 {
		return out
	}
	final := parties[0].Players[0].GetFinalStats()
	for i, v := range final.GetStats() {
		if v != 0 {
			out = append(out, kv{proto.Stat(i).String(), round(v, 2)})
		}
	}
	for i, v := range final.GetPseudoStats() {
		if v != 0 {
			out = append(out, kv{proto.PseudoStat(i).String(), round(v, 3)})
		}
	}
	return out
}

func metricNames(metrics []proto.StatWeightsTargetMetric) []string {
	var names []string
	for _, m := range metrics {
		names = append(names, strings.ToLower(strings.TrimPrefix(m.String(), "StatWeightsTargetMetric")))
	}
	return names
}

// The five actions that do most of the damage, the player's and the pets', and how many actions other than
// automatic attacks were cast at all.
func topActions(metrics *proto.UnitMetrics) ([]omap, int) {
	type row struct {
		id     string
		damage float64
		casts  int32
	}
	var rows []row
	total := 0.0
	casting := 0
	add := func(prefix string, unit *proto.UnitMetrics) {
		for _, action := range unit.Actions {
			r := row{id: prefix + actionName(action.Id)}
			for _, target := range action.Targets {
				r.damage += target.Damage
				r.casts += target.Casts
			}
			total += r.damage
			if r.casts > 0 && action.Id.GetSpellId() != 0 && !action.IsMelee {
				casting++
			}
			rows = append(rows, r)
		}
	}
	add("", metrics)
	for _, pet := range metrics.Pets {
		add("pet:", pet)
	}
	sort.SliceStable(rows, func(i, j int) bool { return rows[i].damage > rows[j].damage })
	var top []omap
	for i := 0; i < len(rows) && i < 5; i++ {
		share := 0.0
		if total > 0 {
			share = rows[i].damage / total
		}
		top = append(top, omap{{"action", rows[i].id}, {"damageShare", round(share, 3)}})
	}
	return top, casting
}

func actionName(id *proto.ActionID) string {
	name := ""
	switch {
	case id.GetSpellId() != 0:
		name = fmt.Sprintf("spell %d", id.GetSpellId())
	case id.GetItemId() != 0:
		name = fmt.Sprintf("item %d", id.GetItemId())
	default:
		name = id.GetOtherId().String()
	}
	if id.GetTag() != 0 {
		name += fmt.Sprintf(" tag %d", id.GetTag())
	}
	return name
}

func summary(part omap) string {
	var dps, quality, note any
	for _, pair := range part {
		switch pair.k {
		case "dps":
			dps = pair.v
		case "baseline":
			for _, b := range pair.v.(omap) {
				if b.k == "quality" {
					quality = b.v
				}
				if b.k == "note" && quality == "failed" {
					note = b.v
				}
			}
		}
	}
	if note != nil {
		return fmt.Sprintf("quality=%v %v", quality, note)
	}
	return fmt.Sprintf("dps=%v quality=%v", dps, quality)
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		s = s[:i]
	}
	return strings.TrimSpace(s)
}

func round(v float64, digits int) float64 {
	p := math.Pow(10, float64(digits))
	return math.Round(v*p) / p
}

// A proto as plain JSON values with sorted keys: protojson's own spacing is not stable between runs.
func plain(m googleProto.Message) any {
	if m == nil || !m.ProtoReflect().IsValid() {
		return nil
	}
	data, err := protojson.Marshal(m)
	if err != nil {
		panic(err)
	}
	var v any
	if err := json.Unmarshal(data, &v); err != nil {
		panic(err)
	}
	return v
}

func hashOf(m googleProto.Message) string {
	data, err := json.Marshal(plain(m))
	if err != nil {
		panic(err)
	}
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

// A JSON object that keeps its keys in the order written.
type kv struct {
	k string
	v any
}
type omap []kv

func (m omap) MarshalJSON() ([]byte, error) {
	var b strings.Builder
	b.WriteByte('{')
	for i, pair := range m {
		if i > 0 {
			b.WriteByte(',')
		}
		key, err := json.Marshal(pair.k)
		if err != nil {
			return nil, err
		}
		value, err := json.Marshal(pair.v)
		if err != nil {
			return nil, err
		}
		b.Write(key)
		b.WriteByte(':')
		b.Write(value)
	}
	b.WriteByte('}')
	return []byte(b.String()), nil
}
