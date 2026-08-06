-- Standalone: luajit mods/career_card/tests/career_card_load_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
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

run.release()
T.finish("career_card_load")
