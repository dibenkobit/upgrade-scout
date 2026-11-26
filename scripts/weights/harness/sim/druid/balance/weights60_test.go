package balance

import (
	"testing"

	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// Balance as the UI's defaults and its only build, 'Default' (ui/specs/druid/balance/defaults.siml): the Pre-BiS
// gear, the Moonkin talents, the Default APL, the consumables and the options, which the Go suite sims too. The
// build's one target dummy, a raid member to heal, is not part of the fight every tree sims.
func TestWeights60(t *testing.T) {
	const defaults = "ui/specs/druid/balance/defaults.siml"
	weights60.Run(t, "sim/druid/balance", []weights60.Tree{{
		Class: "Druid", Tree: "Balance", SimStatus: "Alpha", Reference: proto.Stat_StatSpellDamage,
		Player: weights60.SimlPlayer("../../../"+defaults, ""),
		Baseline: weights60.Baseline{
			Gear:        defaults + " (DefaultGear 'Pre-BiS')",
			Talents:     defaults + " (StandardTalents 'Moonkin')",
			Rotation:    "the APL of " + defaults + " (StandardRotation 'Default')",
			Consumables: defaults,
			Quality:     "preset",
			Note:        "UI preset build 'Default', the spec's default and its only build.",
		},
	}})
}
