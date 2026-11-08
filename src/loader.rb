#==============================================================================
# BS2 Crash Fix - loader
#------------------------------------------------------------------------------
# Game.ini points "Scripts=" at this file instead of Data\Scripts.rvdata2.
# It loads the game's own scripts from Game.rgss3a, runs them in their normal
# order, and runs the patch (src/patch.rb, embedded below by build.py) right
# before "Main". It contains no game code, so it keeps working when the game
# updates, as long as the scripts it patches still exist.
#==============================================================================
module BS2CrashFix
  VERSION = "__VERSION__"
  PATCH_NAME = "BS2 Crash Fix #{VERSION}"

  PATCH_SOURCE = <<'BS2FIX_PATCH_EOF'
__PATCH_SOURCE__
BS2FIX_PATCH_EOF

  def self.run
    scripts = load_data("Data/Scripts.rvdata2")
    main_index = scripts.rindex {|script| script[1] == "Main" } || scripts.size - 1
    patch = [0, PATCH_NAME, Zlib::Deflate.deflate(PATCH_SOURCE)]
    list = scripts.dup
    list.insert(main_index, patch)
    $RGSS_SCRIPTS = list
    list.each_with_index do |script, index|
      code = Zlib::Inflate.inflate(script[2])
      code.force_encoding("UTF-8")
      eval(code, TOPLEVEL_BINDING, sprintf("{%04d}", index), 1)
    end
  end
end

BS2CrashFix.run
