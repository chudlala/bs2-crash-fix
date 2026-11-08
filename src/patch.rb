#==============================================================================
# BS2 Crash Fix - patch                                    (runs before Main)
#------------------------------------------------------------------------------
# 1) Viewport use-after-free
#    Several effect scripts dispose their sprites/planes AFTER the viewport
#    they live on has been freed. RGSS3 then walks freed memory and Game.exe
#    eventually crashes (access violation in RGSS301.dll), most often on
#    battle start or map transfer, when Spriteset_Map is torn down.
#    Fix: dispose those objects while their viewports still exist. The
#    original dispose calls still run afterwards and are harmless no-ops.
#
# 2) Self-switch bloat
#    The New Game+ reset calls adv_self_switches("all","all","all",false),
#    which writes ~50,000 "false" entries into the save and never removes
#    them. Game_SelfSwitches#[] only checks "== true", so a false entry and a
#    missing entry mean exactly the same thing.
#    Fix: store "off" by deleting the entry, and prune dead entries on load.
#    New Game+ still resets everything exactly as before.
#==============================================================================

#--- 1a. Signal Display: dispose self first, then the private viewport --------
%w(SignalDisplayRear_Sprite SignalDisplayMiddle_Plane SignalDisplayFront_Plane).each do |name|
  next unless Object.const_defined?(name)
  Object.const_get(name).class_eval do
    def dispose
      return if disposed?
      vp = viewport
      super
      vp.dispose if vp && !vp.disposed?
    end
  end
end

#--- 1b. Heat Haze: temporary tilemap/sprites before their viewport -----------
if Object.const_defined?(:Heat_Haze)
  class Heat_Haze
    def dispose_heat_haze_map
      vp = @tilemap.viewport
      @character_sprites.each {|sprite| sprite.dispose } if @character_sprites
      @character_sprites = nil
      @tilemap.dispose
      @tilemap = nil
      @tileset = nil
      vp.dispose if vp && !vp.disposed?
    end
  end
end

#--- 1c. Spriteset_Map: free effect sprites while viewports still exist -------
class Spriteset_Map
  alias bs2fix_dispose_viewports dispose_viewports
  def dispose_viewports
    bs2fix_dispose_effects
    bs2fix_dispose_viewports
  end

  def bs2fix_dispose_effects
    @signal_display_set.dispose_signal      if @signal_display_set
    @rich_sunshine_effect_set.dispose       if @rich_sunshine_effect_set
    @rich_fog_effect_set.dispose            if @rich_fog_effect_set
    @heat_haze.dispose                      if @heat_haze
    if $game_temp && $game_temp.respond_to?(:dispose_fallen_leaves)
      $game_temp.dispose_fallen_leaves
    end
  rescue StandardError => e
    p "BS2 Crash Fix: #{e.class}: #{e.message}" if $TEST
  end
end

#--- 2. Self switches: "off" is stored as "absent" ----------------------------
class Game_SelfSwitches
  def []=(key, value)
    if value == true
      @data[key] = true
    else
      @data.delete(key)
    end
    on_change
  end

  def bs2fix_prune
    @data.delete_if {|key, value| value != true }
  end
end

module DataManager
  class << self
    alias bs2fix_extract_save_contents extract_save_contents
    def extract_save_contents(contents)
      bs2fix_extract_save_contents(contents)
      if $game_self_switches.respond_to?(:bs2fix_prune)
        $game_self_switches.bs2fix_prune
      end
    end
  end
end
