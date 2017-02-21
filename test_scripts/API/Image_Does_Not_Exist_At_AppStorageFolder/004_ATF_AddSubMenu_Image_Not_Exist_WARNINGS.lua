-----------------------------Required Shared Libraries---------------------------------------
require('user_modules/all_common_modules')

------------------------------------ Common Variables ---------------------------------------
local storagePath = config.SDLStoragePath
..config.application1.registerAppInterfaceParams.appID.. "_" .. config.deviceMAC.. "/"
local appName = config.application1.registerAppInterfaceParams.appName

-------------------------------------------Preconditions-------------------------------------
-- Register App -> Activate App
common_steps:PreconditionSteps("PreconditionSteps", 7)

--------------------------------------------BODY---------------------------------------------
-- Verify: when all params are correct and image of subMenuIcon doesn't exist
-- SDL->MOB: RPC (success:false, resultCode:"WARNINGS", info:"Reference image(s) not found")
---------------------------------------------------------------------------------------------
function Test:Verify_AllParamsCorrect_ImageNotExist_WARNINGS()
  local cid = self.mobileSession:SendRPC("AddSubMenu",
    {
      menuID = 1000,
      position = 500,
      menuName ="SubMenupositive",
      -- subMenuIcon will be tested when [APPLINK-21293] done
      -- subMenuIcon =
      -- {
      -- value = "invalidImage.png",
      -- imageType ="DYNAMIC"
      -- }
    })
  EXPECT_HMICALL("UI.AddSubMenu",
    {
      menuID = 1000,
      menuParams = {
        position = 500,
        menuName ="SubMenupositive"
      },
      -- subMenuIcon will be tested when [APPLINK-21293] done
      -- subMenuIcon =
      -- {
      -- value = storagePath.."invalidImage.png",
      -- imageType ="DYNAMIC"
      -- }
    })
  :Do(function(_,data)
      self.hmiConnection:SendError(data.id, data.method, "WARNINGS","Reference image(s) not found")
    end)
  EXPECT_RESPONSE(cid, { success = true, resultCode = "WARNINGS", info = "Reference image(s) not found"})
  EXPECT_NOTIFICATION("OnHashChange")
end

-------------------------------------------Postconditions-------------------------------------
common_steps:UnregisterApp("Postcondition_UnRegisterApp", appName)
common_steps:StopSDL("Postcondition_StopSDL")
