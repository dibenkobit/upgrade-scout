package hunter

import (
	"testing"

	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// The three trees as the UI's preset builds bm, mm and sv of ui/specs/hunter/dps/builds, each loaded over
// defaults.siml as the site loads it: talents, gear, APL, pet, consumables and the spec's options.
func TestWeights60(t *testing.T) {
	const specs = "../../ui/specs/hunter/dps"
	tree := func(name string, build string, apl string, note string) weights60.Tree {
		return weights60.Tree{
			Class: "Hunter", Tree: name, SimStatus: "Alpha", Reference: proto.Stat_StatAgility,
			Player: weights60.SimlPlayer(specs+"/defaults.siml", specs+"/builds/"+build+".siml"),
			Baseline: weights60.Baseline{
				Gear:           "ui/specs/hunter/dps/gear_sets/prebis_turret.gear.siml (PreBisTurretGear 'Pre-BiS' of the Turret group)",
				Talents:        "ui/specs/hunter/dps/builds/" + build + ".siml",
				Rotation:       "ui/specs/hunter/dps/apls/" + apl + ".apl.siml",
				Consumables:    "ui/specs/hunter/dps/builds/" + build + ".siml",
				Quality:        "preset",
				Note:           "UI preset build " + build + ".siml over defaults.siml. " + note + " All three trees' builds wear the turret's Pre-BiS set.",
				GearSharedWith: []string{"Beast Mastery", "Marksmanship", "Survival"},
			},
		}
	}
	weights60.Run(t, "sim/hunter", []weights60.Tree{
		tree("Beast Mastery", "bm", "turret_hawk", "With a raptor out."),
		tree("Marksmanship", "mm", "turret", "No pet, as the build says."),
		tree("Survival", "sv", "turret", "No pet, as the build says. The UI also has sv_weave, the spec's default, and sv_melee, each with a set of its own."),
	})
}
