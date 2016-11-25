--[[
This script purpose: Common functions of all other scripts which are implemented for CCS: informing HMI"
--]]
------------------------------------------------------------------------------------------------------
------------------------------------General Settings for Configuration--------------------------------
------------------------------------------------------------------------------------------------------
config.defaultProtocolVersion = 2
config.deviceMAC = "12ca17b49af2289436f303e0166030a21e525d266e209267433801a8fd4071a0"
Test = require('user_modules/connect_without_mobile_connection')
require('cardinalities')
local mobile_session = require('mobile_session')
local tcp = require('tcp_connection')
local file_connection = require('file_connection')
local mobile = require('mobile_connection')
local common_functions = require('user_modules/shared_testcases/commonFunctions')
local common_steps = require('user_modules/shared_testcases/commonSteps')
local common_preconditions = require('user_modules/shared_testcases/commonPreconditions')
local common_testcases = require('user_modules/shared_testcases/commonTestCases')
local sdl_storage_path = config.pathToSDL .. "storage/"
local policy_table = require('user_modules/shared_testcases/testCasesForPolicyTable')
local common_multi_mobile_connections = require('user_modules/common_multi_mobile_connections')
------------------------------------------------------------------------------------------------------
---------------------------------------Common Variables-----------------------------------------------
------------------------------------------------------------------------------------------------------
TEST_NAME = "Informing_HMI:_"
RESPONSE_TIMEOUT = 2000
local CCS_informing_HMI_common_functions = {}
------------------------------------------------------------------------------------------------------
---------------------------------------Common Functions-----------------------------------------------
------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------
-- function: delete sdl_snapshot, delete logs and policy table, connect mobile and register 2 applications 
-- params:
--   mobile_connection_name: mobile connection name
--   mobile_session_name_1: name of first application's mobile session
--   mobile_session_name_2: name of second application's mobile session
--------------------------------------------------------------------------
function PreconditonSteps(mobile_connection_name, mobile_session_name_1, mobile_session_name_2)
  -- delete sdl_snapshot
  os.execute( "rm -f /tmp/fs/mp/images/ivsu_cache/sdl_snapshot.json" )
  -- delete app_info.dat, SmartDeviceLinkCore.log, TransportManager.log, ProtocolFordHandling.log, HmiFrameworkPlugin.log and policy.sqlite
  common_steps:DeleteLogsFileAndPolicyTable()
  common_multi_mobile_connections:PreconditionSteps("Start_SDL_and_Add_Mobile_Connection", 4)
  -- register and activate first application (appID = "0000001")
  common_multi_mobile_connections:AddMobileSession("Add_Mobile_Session_1", mobile_connection_name, mobile_session_name_1)
  common_multi_mobile_connections:RegisterApplication("Register_Application_1", mobile_session_name_1, config.application1.registerAppInterfaceParams)
  common_multi_mobile_connections:ActivateApplication("Activate_Application_1", config.application1.registerAppInterfaceParams.appName)
  -- register second application (appID = "0000002")
  common_multi_mobile_connections:AddMobileSession("Add_Mobile_Session_2", mobile_connection_name, mobile_session_name_2)
  common_multi_mobile_connections:RegisterApplication("Register_Application_2", mobile_session_name_2, config.application2.registerAppInterfaceParams)
end

--------------------------------------------------------------------------
-- function: Convert preload_pt.json file to a json file, which is used to update policy
-- params: no
--------------------------------------------------------------------------
function CCS_informing_HMI_common_functions:ConvertPreloadedToJson()
  -- load data from sdl_preloaded_pt.json
  path_to_file = config.pathToSDL .. "sdl_preloaded_pt.json"
  local file  = io.open(path_to_file, "r")
  local json_data = file:read("*all") 
  file:close()
  -- decode json to array
  local json = require("json") 
  local data = json.decode(json_data)
  local function has_value (tab, val)
    for index, value in ipairs (tab) do
        if value == val then
            return true
        end
    end
    return false
  end
  for k,v in pairs(data.policy_table.functional_groupings) do
    if  has_value(data.policy_table.app_policies.default.groups, k) or 
        has_value(data.policy_table.app_policies.pre_DataConsent.groups, k) then 
    else 
      data.policy_table.functional_groupings[k] = nil 
    end
  end
  return data
end

--------------------------------------------------------------------------
-- function: Create json file for Policy Table Update
-- params:
--   input_data: data table will be encoded to json style and added into file
--   json_file_path: path of json file which will be used for policy updating
--   json_file_path_debug: path of debug json file, keep for debug only. If value == nil then do not save file for debug
--------------------------------------------------------------------------
function CCS_informing_HMI_common_functions:CreateJsonFileForPTU(input_data, json_file_path, json_file_path_debug)
  -- save file for update policy
  local json = require("json")
  data = json.encode(input_data)
  file = io.open(json_file_path, "w")
  file:write(data)
  file:close()  
 	-- save file for debugging
  if json_file_path_debug then
    file_debug = io.open(json_file_path_debug, "w")
    file_debug:write(data)
    file_debug:close()
  end
end

--------------------------------------------------------------------------
-- function: Update policy
-- params:
--   self
--   json_file_path: path of json file which will be used for policy updating
--   input_app_id: appID of application which policy will be updated. If value == nil then use id of first app
--------------------------------------------------------------------------
function CCS_informing_HMI_common_functions:UpdatePolicy(self, json_file_path, input_app_id)
  if not input_app_id then
    input_app_id = self.applications[config.application1.registerAppInterfaceParams.appName]
  end 
  --hmi side: sending SDL.GetURLS request
  local request_id_get_urls = self.hmiConnection:SendRequest("SDL.GetURLS", { service = 7 }) 
  --hmi side: expect SDL.GetURLS response from HMI
  EXPECT_HMIRESPONSE(request_id_get_urls,{result = {code = 0, method = "SDL.GetURLS", urls = {{url = "http://policies.telematics.ford.com/api/policies"}}}})
  :Do(function(_,data)
    --hmi side: sending BasicCommunication.OnSystemRequest request to SDL
    self.hmiConnection:SendNotification("BasicCommunication.OnSystemRequest", {
      requestType = "PROPRIETARY",
      fileName = "filename"
    })
    --mobile side: expect OnSystemRequest notification 
    EXPECT_NOTIFICATION("OnSystemRequest", { requestType = "PROPRIETARY" })
    :Do(function(_,data)
      --mobile side: sending SystemRequest request 
      local corid = self.mobileSession:SendRPC("SystemRequest",{
        fileName = "PolicyTableUpdate",
        requestType = "PROPRIETARY",
        appID = input_app_id
      },
      json_file_path
      )
      local system_request_id
      --hmi side: expect SystemRequest request
      EXPECT_HMICALL("BasicCommunication.SystemRequest")
      :Do(function(_,data)
        system_request_id = data.id 
        --hmi side: sending BasicCommunication.OnSystemRequest request to SDL
        self.hmiConnection:SendNotification("SDL.OnReceivedPolicyUpdate",
        {
          policyfile = "/tmp/ptu_update.json"
        }
        )
        function to_run()
          --hmi side: sending SystemRequest response
          self.hmiConnection:SendResponse(system_request_id,"BasicCommunication.SystemRequest", "SUCCESS", {})
        end
        
        RUN_AFTER(to_run, 500)
      end)
      --hmi side: expect SDL.OnStatusUpdate
      EXPECT_HMINOTIFICATION("SDL.OnStatusUpdate")
      :ValidIf(function(exp,data)
        if 
        exp.occurences == 1 and
        data.params.status == "UP_TO_DATE" then
          return true
        elseif
        exp.occurences == 1 and
        data.params.status == "UPDATING" then
          return true
        elseif
        exp.occurences == 2 and
        data.params.status == "UP_TO_DATE" then
          return true
        else 
          if 
          exp.occurences == 1 then
            print ("\27[31m SDL.OnStatusUpdate came with wrong values. Expected in first occurrences status 'UP_TO_DATE' or 'UPDATING', got '" .. tostring(data.params.status) .. "' \27[0m")
          elseif exp.occurences == 2 then
            print ("\27[31m SDL.OnStatusUpdate came with wrong values. Expected in second occurrences status 'UP_TO_DATE', got '" .. tostring(data.params.status) .. "' \27[0m")
          end
          return false
        end
      end)
      :Times(Between(1,2))
      --mobile side: expect SystemRequest response
      EXPECT_RESPONSE(corid, { success = true, resultCode = "SUCCESS"})
      :Do(function(_,data)
        --hmi side: sending SDL.GetUserFriendlyMessage request to SDL
        local request_id_GetUserFriendlyMessage = self.hmiConnection:SendRequest("SDL.GetUserFriendlyMessage", {language = "EN-US", messageCodes = {"StatusUpToDate"}}) 
        --hmi side: expect SDL.GetUserFriendlyMessage response
        EXPECT_HMIRESPONSE(request_id_GetUserFriendlyMessage,{result = {code = 0, method = "SDL.GetUserFriendlyMessage", messages = {{line1 = "Up-To-Date", messageCode = "StatusUpToDate", textBody = "Up-To-Date"}}}})
      end) -- Do EXPECT_RESPONSE: SystemRequest response 
    end) -- Do EXPECT_NOTIFICATION: "OnSystemRequest" notification
  end) -- Do EXPECT_HMIRESPONSE: SDL.GetURLS response from HMI	
end

--------------------------------------------------------------------------
-- function: Validate "id" params of AllowedFunctions array in SDL's GetListOfPermissions response to HMI
-- params:
--   data: data from the SDL.GetListOfPermissions response
--   allowed_functions_name: specific function name in AllowedFunctions array
--------------------------------------------------------------------------
function CCS_informing_HMI_common_functions:Validate_AllowedFunctions_Id(data, allowed_functions_name)
  local validate = false
  for i = 1, #data.result.allowedFunctions do
    if data.result.allowedFunctions[i].name == allowed_functions_name then
      if data.result.allowedFunctions[i].id ~= nil then 
        validate = true
      else
        common_functions:printError("Error: userConsent function: function group " .. allowed_functions_name .. " does not exist.") 
      end
      break
    end					
  end
  return validate
end

--------------------------------------------------------------------------
-- function: Validate "entityType" and "entityId" params of ccsStatus array in SDL's GetListOfPermissions response to HMI
-- params:
--   data: data from the SDL.GetListOfPermissions response
--   entity_type: specific function name in AllowedFunctions array
--   entity_id: specific function name in AllowedFunctions array
--------------------------------------------------------------------------
function CCS_informing_HMI_common_functions:Validate_ccsStatus_EntityType_EntityId(data, entity_type, entity_id)
  local validate = false
  for i = 1, #data.result.ccsStatus do
    if data.result.ccsStatus[i].entityType == entity_type and data.result.ccsStatus[i].entityID == entity_id then
        validate = true
        break
    end
  end
  return validate
end

return CCS_informing_HMI_common_functions
