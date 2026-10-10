--!strict
-- Test-only builder (tests/shop/decor.sh copies it into a private tree): the real headquarters plus the
-- shop's cosmetic decor, so harness/build_dump.luau --module can dump, check and render it.
local Design = require(script.Parent.HeadquartersDesign)
local ShopDecor = require(script.Parent.ShopDecor)
local Build = {}
function Build.build(cf: CFrame, session: any, accent: Color3): Model
	local office = Design.build(cf, session, accent)
	ShopDecor.party(office, cf, session.data.company.name)
	ShopDecor.founderSuite(office, cf, session.data.empire.office)
	return office
end
return Build
