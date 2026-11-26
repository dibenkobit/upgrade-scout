package mage

import (
	"testing"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
	googleProto "google.golang.org/protobuf/proto"
)

// The three trees as the UI's preset builds 'Arcane', 'Fire' and 'Frost Incin' of ui/specs/mage/dps/presets.ts,
// which the Go suites arcaneSuite, fireSuite and frostSuite already sim: the same talents and APL files. Each
// build wears the Preraid gear set of its tree.
func TestWeights60(t *testing.T) {
	// DefaultConsumables of the UI presets. The Go suite's differ in one elixir: Greater Mageblood Elixir where the
	// UI has Mageblood Elixir.
	consumables := &proto.ConsumesSpec{
		FlaskId:         13512,
		ElixirIds:       []int32{13454, 250348, 20007},
		FoodId:          13931,
		MhImbueId:       20749,
		MhWeaponImbueId: 277502,
		ResourcePotId:   13444,
	}
	// The Fire build's: Scroll of Imbue Greater Flame in place of Scroll of Imbue Precision.
	fireConsumables := googleProto.Clone(consumables).(*proto.ConsumesSpec)
	fireConsumables.MhWeaponImbueId = 277500

	build := func(config core.CharacterSuiteConfig, gear string, consumables *proto.ConsumesSpec, distance float64) *core.CharacterSuiteConfig {
		config.GearSet = weights60.Gear("../../ui/specs/mage/dps/gear_sets", gear)
		config.Consumables = consumables
		config.StartingDistance = distance // OtherDefaults and FrostSettings of the UI presets.
		config.ChannelClipDelayMs = 100
		return &config
	}
	const consumablesName = "DefaultConsumables of ui/specs/mage/dps/presets.ts"

	weights60.Run(t, "sim/mage", []weights60.Tree{
		{
			Class: "Mage", Tree: "Arcane", SimStatus: "Alpha", Reference: proto.Stat_StatSpellDamage,
			Config: build(arcaneSuite(), "preraid", consumables, 20),
			Baseline: weights60.Baseline{
				Gear:        "ui/specs/mage/dps/gear_sets/preraid.gear.json (PreRaidArcaneGear 'Preraid' of the Arcane group)",
				Talents:     "ArcaneTalents 'Arcane'",
				Rotation:    "ui/specs/mage/dps/apls/arcane.apl.json (ArcaneAplPreset 'Arcane')",
				Consumables: consumablesName,
				Quality:     "preset",
				Note:        "UI preset build 'Arcane'. The UI also has the build 'Arcane Fire'.",
			},
		},
		{
			Class: "Mage", Tree: "Fire", SimStatus: "Alpha", Reference: proto.Stat_StatSpellDamage,
			Config: build(fireSuite(), "preraidFire", fireConsumables, 20),
			Baseline: weights60.Baseline{
				Gear:        "ui/specs/mage/dps/gear_sets/preraidFire.gear.json (PreRaidFireGear 'Preraid' of the Fire group)",
				Talents:     "FireTalents 'Fire'",
				Rotation:    "ui/specs/mage/dps/apls/deepFire.apl.json (FireAplPreset 'Fire')",
				Consumables: consumablesName + ", with Scroll of Imbue Greater Flame on the weapon as the Fire build has it",
				Quality:     "preset",
				Note:        "UI preset build 'Fire'. The UI also has the build 'FFB', on the same gear set.",
			},
		},
		{
			Class: "Mage", Tree: "Frost", SimStatus: "Alpha", Reference: proto.Stat_StatSpellDamage,
			Config: build(frostSuite(), "preraidFrost", consumables, 28),
			Baseline: weights60.Baseline{
				Gear:        "ui/specs/mage/dps/gear_sets/preraidFrost.gear.json (PreRaidFrostGear 'Preraid' of the Frost group)",
				Talents:     "FrostIncinTalents 'Frost Incin'",
				Rotation:    "ui/specs/mage/dps/apls/frost.apl.json (FrostAplPreset 'Frost')",
				Consumables: consumablesName,
				Quality:     "preset",
				Note:        "UI preset build 'Frost Incin', whose settings name only the distance: the consumables are the page's defaults. The UI also has the build 'Frost Med', on the same gear set.",
			},
		},
	})
}
