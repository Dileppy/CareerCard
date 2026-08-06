-- Standalone: luajit mods/career_card/tests/career_card_load_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Manifest = require("src.mods.Manifest")
-- fixtures.fresh(), NOT Data:load(). Data:load() reads data/generated/*,
-- which only exists after a ROM import, and errors with "missing generated
-- data module" on a clean checkout. The fixture dataset is the documented
-- ROM-free path and is what makes these suites runnable anywhere.
local Data = T.fixtures.fresh()

local run = T.sdk.loadMod("mods/career_card", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
T.check(run.mod ~= nil, "the loader returned a mod record")
T.eq(run.mod.manifest.id, "career_card", "id is career_card")
T.eq(run.mod.manifest.api, 2, "targets mod api 2")
T.eq(#(run.mod.manifest.permissions or {}), 0, "requests no permissions")

-- ------- link compatibility is DECLARED, not merely true
--
-- src/link/Handshake.lua:43 reads `manifest.affects_link ~= false`, so an
-- OMITTED field means the mod is treated as link-affecting. 1.0.0 shipped
-- without it and every player who installed it was flagged incompatible for
-- trading and link battles, despite the mod changing no battle mechanics at
-- all. Silence is not a claim here; only the literal `false` is.
T.eq(run.mod.manifest.raw.affects_link, false,
  "the manifest explicitly declares affects_link = false")
T.eq(run.mod.manifest.affects_link, false,
  "...and the parsed manifest agrees, so the handshake sees it")

-- The declaration has to stay HONEST. The loader warns when a mod swears it
-- is link-safe while writing into a link-relevant registry
-- (src/mods/Loader.lua:806-816). Assert the underlying fact directly rather
-- than trusting the absence of a log line: this mod may only ever READ
-- content.pokemon to count species, never register into it.
for name in pairs(Manifest.LINK_REGISTRIES) do
  local registry = run.loader.content[name]
  local wrote = false
  if registry and registry.ops then
    for _, list in pairs(registry.ops) do
      for _, entry in ipairs(list) do
        if entry.owner == "career_card" then wrote = true end
      end
    end
  end
  T.check(not wrote,
    ("career_card must not write to the link registry %q"):format(name))
end

run.release()
T.finish("career_card_load")
