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
#    The damage popup script also abandons popup sprites (1d). Crash dumps
#    show the actual crash: Ruby's GC frees an undisposed Sprite whose
#    viewport was already freed. Section 0 makes that impossible for any
#    script: a viewport disposes its live sprites/planes before it goes.
#
# 2) Self-switch bloat
#    The New Game+ reset calls adv_self_switches("all","all","all",false),
#    which writes ~50,000 "false" entries into the save and never removes
#    them. Game_SelfSwitches#[] only checks "== true", so a false entry and a
#    missing entry mean exactly the same thing.
#    Fix: store "off" by deleting the entry, and prune dead entries on load.
#    New Game+ still resets everything exactly as before.
#==============================================================================

#--- 0. Safety net: a viewport never outlives its live children ---------------
# Every Sprite/Plane created on (or moved to) a viewport is remembered by that
# viewport. Disposing a sprite/plane forgets it again, so nothing piles up.
# When a viewport is disposed, any child some script forgot to dispose is
# disposed first, so Ruby's GC can never later free a sprite whose viewport
# is already gone (the RGSS301.dll+0x111a1c crash).
class Viewport
  alias bs2fix_viewport_dispose dispose
  def dispose
    children = @bs2fix_children
    @bs2fix_children = nil
    if children && !disposed?
      children.each do |child|
        begin
          child.dispose unless child.disposed?
        rescue StandardError
        end
      end
    end
    bs2fix_viewport_dispose
  end

  def bs2fix_add_child(child)
    return if disposed?
    (@bs2fix_children ||= []) << child
  end

  def bs2fix_remove_child(child)
    @bs2fix_children.delete(child) if @bs2fix_children
  end
end

class Sprite
  alias bs2fix_sprite_initialize initialize
  def initialize(*args)
    bs2fix_sprite_initialize(*args)
    args[0].bs2fix_add_child(self) if args[0].is_a?(Viewport)
  end

  alias bs2fix_sprite_dispose dispose
  def dispose
    unless disposed?
      vp = viewport
      vp.bs2fix_remove_child(self) if vp
    end
    bs2fix_sprite_dispose
  end

  if method_defined?(:viewport=)
    alias bs2fix_sprite_set_viewport viewport=
    def viewport=(vp)
      old = viewport
      bs2fix_sprite_set_viewport(vp)
      unless old.equal?(vp)
        old.bs2fix_remove_child(self) if old
        vp.bs2fix_add_child(self) if vp.is_a?(Viewport)
      end
    end
  end
end

class Plane
  alias bs2fix_plane_initialize initialize
  def initialize(*args)
    bs2fix_plane_initialize(*args)
    args[0].bs2fix_add_child(self) if args[0].is_a?(Viewport)
  end

  alias bs2fix_plane_dispose dispose
  def dispose
    unless disposed?
      vp = viewport
      vp.bs2fix_remove_child(self) if vp
    end
    bs2fix_plane_dispose
  end

  if method_defined?(:viewport=)
    alias bs2fix_plane_set_viewport viewport=
    def viewport=(vp)
      old = viewport
      bs2fix_plane_set_viewport(vp)
      unless old.equal?(vp)
        old.bs2fix_remove_child(self) if old
        vp.bs2fix_add_child(self) if vp.is_a?(Viewport)
      end
    end
  end
end

#--- 1a. Signal Display: dispose self first, then the private viewport --------
# (Each class is reopened separately: Ruby 1.9.2 can't call super from one
#  method body shared by several classes.)
if Object.const_defined?(:SignalDisplayRear_Sprite)
  class SignalDisplayRear_Sprite
    def dispose
      return if disposed?
      vp = viewport
      super
      vp.dispose if vp && !vp.disposed?
    end
  end
end

if Object.const_defined?(:SignalDisplayMiddle_Plane)
  class SignalDisplayMiddle_Plane
    def dispose
      return if disposed?
      vp = viewport
      super
      vp.dispose if vp && !vp.disposed?
    end
  end
end

if Object.const_defined?(:SignalDisplayFront_Plane)
  class SignalDisplayFront_Plane
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

#--- 1d. Damage popups ("damage pop" script): never abandon a popup sprite ---
# The popup script creates a Sprite on the battler's viewport for every damage
# number, but (a) never disposes popups still on screen when the battler
# sprite is disposed (battle end), and (b) when a popup finishes it removes
# the FIRST list entry instead of the finished one, dropping a live sprite.
# Either way an undisposed sprite outlives its viewport, and when Ruby's GC
# later frees it, RGSS3 crashes (RGSS301.dll+0x111a1c).
if Sprite_Battler.method_defined?(:update_damage_pop)
  class Sprite_Battler
    alias bs2fix_popup_dispose dispose
    def dispose
      bs2fix_dispose_popups
      bs2fix_popup_dispose
    end

    def bs2fix_dispose_popups
      (@_damage_sprites || []).each do |pair|
        sprite = pair && pair[0]
        next if sprite.nil? || sprite.disposed?
        sprite.bitmap.dispose if sprite.bitmap && !sprite.bitmap.disposed?
        sprite.dispose
      end
      @_damage_sprites = []
      @old_d = []
    end

    # Same animation as the original; only the clean-up is corrected.
    def update_damage_pop
      return unless @use_sprite
      return if @_damage_sprites == nil or @_damage_sprites.empty?
      return dispose_damage if (@battler.hidden?) and not popup?
      a = POPUP_DURATION
      finished = []
      @_damage_sprites.each_index do |index|
        sprite_array = @_damage_sprites[index]
        sprite = sprite_array[0]
        d = sprite_array[1]
        if sprite == nil or sprite.disposed?
          finished << index
          next
        end
        if index > 0 and @old_d[index - 1] != nil and @old_d[index - 1] > (POPUP_DURATION / 2)
          sprite.visible = false
          next
        else
          sprite.visible = true
        end
        if d > 0
          d -= 1
          case d
          when a - 2..a - 1
            sprite.y -= 4
          when a - 4..a - 3
            sprite.y -= 2
          when a - 6..a - 5
            sprite.y += 2
          when a - 12..a - 7
            sprite.y += 4
          end
          sprite.opacity = 256 - (12 - d) * 32
          if d <= 0
            sprite.bitmap.dispose if sprite.bitmap && !sprite.bitmap.disposed?
            sprite.dispose
            finished << index
          end
        end
        sprite_array[1] = d
        @old_d[index] = d
      end
      finished.reverse_each do |index|
        @_damage_sprites.delete_at(index)
        @old_d.delete_at(index)
      end
      dispose_damage if @_damage_sprites.empty?
    end
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
