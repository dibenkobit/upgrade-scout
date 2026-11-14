package mage

import (
	"testing"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// The three trees as the UI's preset builds 'Arcane', 'Fire' and 'Frost Incin' of ui/specs/mage/dps/presets.ts,
// which the Go suites arcaneSuite, fireSuite and frostSuite already sim: the same talents and APL files. The UI
// has one gear set for the class, P1 Arcane, and every build uses it.
func TestWeights60(t *testing.T) {
	// DefaultConsumables of the UI presets. The Go suite's differ in one elixir: Greater Mageblood Elixir where the
	// UI has Mageblood Elixir.
	consumables := &proto.ConsumesSpec{
		FlaskId:         13512,
		ElixirIds:       []int32{13454, 13447, 250348, 20007},
		FoodId:          13931,
		MhImbueId:       20749,
		MhWeaponImbueId: 277502,
		ResourcePotId:   13444,
	}
	build := func(config core.CharacterSuiteConfig, distance float64) *core.CharacterSuiteConfig {
		config.Consumables = consumables
		config.StartingDistance = distance // OtherDefaults and FrostSettings of the UI presets.
		config.ChannelClipDelayMs = 100
		return &config
	}
	const gear = "ui/specs/mage/dps/gear_sets/p1Arcane.gear.json (P1ArcaneGear 'P1 Arcane')"
	const consumablesName = "DefaultConsumables of ui/specs/mage/dps/presets.ts"
	shared := []string{"Arcane", "Fire", "Frost"}

	weights60.Run(t, "sim/mage", []weights60.Tree{
		{
			Class: "Mage", Tree: "Arcane", SimStatus: "Alpha", Reference: proto.Stat_StatSpellDamage,
			Config: build(arcaneSuite(), 20),
			Baseline: weights60.Baseline{
				Gear:           gear,
				Talents:        "ArcaneTalents 'Arcane'",
				Rotation:       "ui/specs/mage/dps/apls/arcane.apl.json (ArcaneAplPreset 'Arcane')",
				Consumables:    consumablesName,
				Quality:        "preset",
				Note:           "UI preset build 'Arcane'. The gear preset is marked devOnly in the UI. The UI also has the build 'Arcane Fire'.",
				GearSharedWith: shared,
			},
		},
		{
			Class: "Mage", Tree: "Fire", SimStatus: "Alpha", Reference: proto.Stat_StatSpellDamage,
			Config: build(fireSuite(), 20),
			Baseline: weights60.Baseline{
				Gear:           gear,
				Talents:        "FireTalents 'Fire'",
				Rotation:       "ui/specs/mage/dps/apls/deepFire.apl.json (FireAplPreset 'Fire')",
				Consumables:    consumablesName,
				Quality:        "testing",
				Note:           "UI preset build 'Fire', but the repo has no Fire gear set: the build sims on the Arcane set, with whatever Arcane-only stats and set bonuses that carries. The UI also has the build 'FFB'.",
				GearSharedWith: shared,
			},
		},
		{
			Class: "Mage", Tree: "Frost", SimStatus: "Alpha", Reference: proto.Stat_StatSpellDamage,
			Config: build(frostSuite(), 28),
			Baseline: weights60.Baseline{
				Gear:           gear,
				Talents:        "FrostIncinTalents 'Frost Incin'",
				Rotation:       "ui/specs/mage/dps/apls/frost.apl.json (FrostAplPreset 'Frost')",
				Consumables:    consumablesName,
				Quality:        "testing",
				Note:           "UI preset build 'Frost Incin', but the repo has no Frost gear set: the build sims on the Arcane set, with whatever Arcane-only stats and set bonuses that carries. The UI also has the build 'Frost Med'.",
				GearSharedWith: shared,
			},
		},
	})
}
