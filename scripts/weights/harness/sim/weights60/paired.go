package weights60

// A paired stat weight runner of its own, for what core.StatWeights does not measure: a step below the
// baseline for hit and expertise, which the engine weighs above the baseline only, and the precision of
// damage taken and TMI, which its iteration target does not cover. It pairs runs the way the engine does:
// every request runs with the engine's labeled random numbers, iteration i at seed+i, so a modified run's
// iteration i meets the same rolls as the unmodified run's iteration i, and the weight is the mean of the
// per-iteration differences over the step.

import (
	"fmt"
	"math"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
)

const (
	mDps = iota
	mTps
	mDtps
	mTmi
	metricCount
)

var metricKeys = [metricCount]string{"dps", "tps", "dtps", "tmi"}

type runValues [metricCount][]float64

func valuesOfRun(result *proto.RaidSimResult, iterations int) (runValues, error) {
	player := result.RaidMetrics.Parties[0].Players[0]
	values := runValues{player.Dps.AllValues, player.Threat.AllValues, player.Dtps.AllValues, player.Tmi.AllValues}
	for m := range values {
		if len(values[m]) == 0 {
			values[m] = make([]float64, iterations)
		}
		if len(values[m]) != iterations {
			return values, fmt.Errorf("the sim returned %d %s values for %d iterations", len(values[m]), metricKeys[m], iterations)
		}
	}
	return values, nil
}

// One request, run in pieces. Iteration i always runs at seed+i, so a series extended in several runs holds
// exactly what one longer run would.
type series struct {
	name       string
	request    *proto.RaidSimRequest
	seed       int64
	done       int
	keep       bool // Whether the per-iteration values are kept, for the series other runs pair with.
	values     runValues
	iterations int64 // Iterations simmed, for the time report.
}

func newSeries(name string, request *proto.RaidSimRequest, seed int64, keep bool) *series {
	request = clone(request)
	request.SimOptions.SaveAllValues = true
	request.SimOptions.UseLabeledRands = true
	request.SimOptions.IsTest = false
	return &series{name: name, request: request, seed: seed, keep: keep}
}

// Runs the series on to iteration to and returns the values of the iterations it added, which start at from.
func (s *series) extend(to int) (added runValues, from int, err error) {
	from = s.done
	if to <= from {
		return added, from, nil
	}
	request := clone(s.request)
	request.SimOptions.Iterations = int32(to - from)
	request.SimOptions.RandomSeed = s.seed + int64(from)
	result := core.RunRaidSimConcurrent(request)
	if result.Error != nil {
		return added, from, fmt.Errorf("%s: %s", s.name, firstLine(result.Error.Message))
	}
	added, err = valuesOfRun(result, to-from)
	if err != nil {
		return added, from, fmt.Errorf("%s: %w", s.name, err)
	}
	if s.keep {
		for m := range added {
			s.values[m] = append(s.values[m], added[m]...)
		}
	}
	s.done = to
	s.iterations += int64(to - from)
	return added, from, nil
}

// Sums of paired samples, merged the way the engine merges its two sides: one pool of per-point samples.
type sums struct {
	n          int
	sum, sumSq float64
}

func (a *sums) add(x float64) {
	a.n++
	a.sum += x
	a.sumSq += x * x
}

func (a sums) merge(b sums) sums {
	return sums{n: a.n + b.n, sum: a.sum + b.sum, sumSq: a.sumSq + b.sumSq}
}

// The mean and the population standard deviation, as the engine's aggregator gives them.
func (a sums) meanStdev() (float64, float64) {
	if a.n == 0 {
		return 0, 0
	}
	mean := a.sum / float64(a.n)
	variance := a.sumSq/float64(a.n) - mean*mean
	return mean, math.Sqrt(math.Max(variance, 0))
}

// One side of a measurement: the run with the stat moved by mod, paired with the run it is compared with.
type side struct {
	from *series // Kept values.
	to   *series
	mod  float64
	sums [metricCount]sums
	// Whether every paired sample so far was exactly 0 in every metric.
	identical bool
}

func (s *side) extend(n int) error {
	if _, _, err := s.from.extend(n); err != nil {
		return err
	}
	added, start, err := s.to.extend(n)
	if err != nil {
		return err
	}
	if s.sums[0].n == 0 && start == 0 {
		s.identical = true
	}
	for m := range added {
		for j, value := range added[m] {
			sample := (value - s.from.values[m][start+j]) / s.mod
			if sample != 0 {
				s.identical = false
			}
			s.sums[m].add(sample)
		}
	}
	return nil
}

// A stat's weight from one or two sides.
type measure struct {
	name  string
	sides []*side
}

func (m *measure) pooled(metric int) sums {
	var total sums
	for _, s := range m.sides {
		total = total.merge(s.sums[metric])
	}
	return total
}

func (m *measure) identical() bool {
	for _, s := range m.sides {
		if !s.identical {
			return false
		}
	}
	return true
}

func (m *measure) perSide() int {
	most := 0
	for _, s := range m.sides {
		most = max(most, s.to.done)
	}
	return most
}

// An interval a measurement is run down to: metric's EP against the reference measurement's weight in
// the same metric.
type goal struct {
	metric    int
	epCi      float64
	reference *measure
}

type plan struct {
	measure *measure
	goals   []goal
	cap     int // The most iterations one side may take.
}

// Runs every plan's sides to probe iterations, then tops each side up until its goals are met or the cap is
// reached, sized each time from the spread seen so far. The goals are asked of the runs at share of their
// interval, since the sizing works from estimates.
func runPlans(plans []*plan, probe int, passes int, share float64) error {
	for _, p := range plans {
		for _, s := range p.measure.sides {
			if err := s.extend(min(probe, p.cap)); err != nil {
				return err
			}
		}
	}
	for pass := 0; pass < passes; pass++ {
		type step struct {
			side *side
			to   int
		}
		var steps []step
		for _, p := range plans {
			need := 0
			for _, g := range p.goals {
				if n := neededPairs(p.measure, g, share); n > need {
					need = n
				}
			}
			perSide := int(math.Ceil(float64(need) / float64(len(p.measure.sides))))
			perSide = min(perSide, p.cap)
			for _, s := range p.measure.sides {
				if perSide > s.to.done {
					steps = append(steps, step{s, perSide})
				}
			}
		}
		if len(steps) == 0 {
			return nil
		}
		// Extend the series the others pair with first, in one run each, as far as any side needs.
		furthest := map[*series]int{}
		for _, st := range steps {
			furthest[st.side.from] = max(furthest[st.side.from], st.to)
		}
		for from, to := range furthest {
			if _, _, err := from.extend(to); err != nil {
				return err
			}
		}
		for _, st := range steps {
			if err := st.side.extend(st.to); err != nil {
				return err
			}
		}
	}
	return nil
}

// The pooled pairs a measurement needs for the goal's interval at share of it, 0 when its weight or the
// reference weight is 0.
func neededPairs(m *measure, g goal, share float64) int {
	weight, stdev := m.pooled(g.metric).meanStdev()
	reference, _ := g.reference.pooled(g.metric).meanStdev()
	if weight == 0 && stdev == 0 || reference == 0 {
		return 0
	}
	epStdev := stdev / math.Abs(reference)
	return int(math.Ceil(math.Pow(core.StatWeightZ90*epStdev/(g.epCi*share), 2) * 1.05))
}

// A measurement's weight in one metric against a reference measurement, in the output's shape.
func (m *measure) entry(metric int, reference *measure, valueKey string) (omap, float64) {
	pool := m.pooled(metric)
	weight, stdev := pool.meanStdev()
	ref, _ := reference.pooled(metric).meanStdev()
	n := float64(max(pool.n, 1))
	ep, epCi := 0.0, 0.0
	if ref != 0 {
		ep = weight / ref
		epCi = core.StatWeightZ90 * stdev / math.Abs(ref) / math.Sqrt(n)
	}
	out := omap{
		{valueKey, weight},
		{"stdev", stdev},
		{"n", pool.n},
		{"ep", ep},
		{"ci90", core.StatWeightZ90 * stdev / math.Sqrt(n)},
		{"epCi90", epCi},
	}
	if m.identical() {
		out = append(out, kv{"identicalToBaseline", true})
	}
	return out, epCi
}
