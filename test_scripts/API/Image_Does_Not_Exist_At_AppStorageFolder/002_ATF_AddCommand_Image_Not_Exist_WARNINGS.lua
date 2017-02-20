-----------------------------Required Shared Libraries---------------------------------------
require('user_modules/all_common_modules')

------------------------------------ Common Variables ---------------------------------------
local storagePath = config.pathToSDL .. "storage/"
..config.application1.registerAppInterfaceParams.appID.. "_" .. config.deviceMAC.. "/"
local appName = config.application1.registerAppInterfaceParams.appName

-------------------------------------------Preconditions-------------------------------------
--Register App -> Activate App
common_steps:PreconditionSteps("PreconditionSteps", 7)

--------------------------------------------BODY---------------------------------------------
-- Verify: when all params are correct and image of cmdIcon doesn't exist
-- SDL->MOB: RPC (success:false, resultCode:"WARNINGS", info:"Reference image(s) not found")
---------------------------------------------------------------------------------------------
function Test:Verify_AllParamsCorrect_ImageNotExist_WARNINGS()
  local cid = self.mobileSession:SendRPC("AddCommand",
    {
      cmdID = 11,
      menuParams =
      {
        position = 0,
        menuName ="Commandpositive"
      },
      vrCommands =
      {
        "VRCommandonepositive",
        "VRCommandonepositivedouble"
      },
      cmdIcon =
      {
        value = storagePath.."icon888.png",
        imageType ="DYNAMIC"
      }
    })
  EXPECT_HMICALL("UI.AddCommand",
    {
      cmdID = 11,
      cmdIcon =
      {
        value = storagePath.."icon888.png",
        imageType = "DYNAMIC"
      },
      menuParams =
      {
        position = 0,
        menuName ="Commandpositive"
      }
    })
  :Do(function(_,data)
      self.hmiConnection:SendError(data.id, data.method, "WARNINGS","Reference image(s) not found")
    end)
  EXPECT_HMICALL("VR.AddCommand",
    {
      cmdID = 11,
      type = "Command",
      vrCommands =
      {
        "VRCommandonepositive",
        "VRCommandonepositivedouble"
      }
    })
  :Do(function(_,data)
      self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
    end)
  EXPECT_RESPONSE(cid, {success = true, resultCode = "WARNINGS", info = "Reference image(s) not found"})
  EXPECT_NOTIFICATION("OnHashChange")
end

-------------------------------------------Postconditions-------------------------------------
common_steps:UnregisterApp("Postcondition_UnRegisterApp", appName)
common_steps:StopSDL("Postcondition_StopSDL")
