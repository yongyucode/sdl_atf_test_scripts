--------------------------------------------------------------------------------
-- This script covers requirement[HMILevel resumption] [Ford-Specific]: Media app (or navi, voice-com) is registered during OnEventChanged (EMERGENCY_EVENT, isActive=true)
--------------------------------------------------------------------------------
--[[In case
the media app (or navi, voice-com) satisfies the conditions of successful HMILevel resumption (unexpected disconnect, next ignition cycle, short ignition cycle, low voltage)
and SDL receives OnEventChanged (EMERGENCY_EVENT, isActive=true)) notification
SDL must:
postpone resuming HMILevel of media app
assign <default_HMI_level> to this media app (meaning: by sending OnHMIStatus notification to mobile app per current req-s)
resume HMILevel after event ends (SDL receives OnEventChanged (EMERGENCY_EVENT, isActive=false) notification)
]]
-----------------------------Required Shared Libraries---------------------------------------
require('user_modules/all_common_modules')
------------------------------------ Common Variables ---------------------------------------
local tc_number = 1
local mobile_session_name = "mobileSession"
local apps = {}
apps[1] = common_functions:CreateRegisterAppParameters({appID = "1", appName = "NAVIGATION", isMediaApplication = false, appHMIType = {"NAVIGATION"}})
apps[2] = common_functions:CreateRegisterAppParameters({appID = "2", appName = "COMMUNICATION", isMediaApplication = false, appHMIType = {"COMMUNICATION"}})
apps[3] = common_functions:CreateRegisterAppParameters({appID = "3", appName = "MEDIA", isMediaApplication = true, appHMIType = {"MEDIA"}})
apps[4] = common_functions:CreateRegisterAppParameters({appID = "4", appName = "NON_MEDIA", isMediaApplication = false, appHMIType = {"DEFAULT"}})
-------------------------------------------Preconditions-------------------------------------
common_steps:BackupFile("Backup Ini file", "smartDeviceLink.ini")
common_steps:SetValuesInIniFile("Update ApplicationResumingTimeout value", "%p?ApplicationResumingTimeout%s? = %s-[%d]-%s-\n", "ApplicationResumingTimeout", 5000)
common_steps:PreconditionSteps("Precondition", 5)
-----------------------------------------------Body------------------------------------------
-- Start Emergency
-- @param test_case_name: main test name 
---------------------------------------------------------------------------------------------
function StartEmergency(test_case_name, event)	
	Test[test_case_name] = function(self)
		self.hmiConnection:SendNotification("BasicCommunication.OnEventChanged", {isActive = true, eventName = "EMERGENCY_EVENT"})	
	end	
end
---------------------------------------------------------------------------------------------
-- Stop Emergency with delay time
-- @param test_case_name: main test name
-- @param delay_time: the time that Emergency will be stopped
---------------------------------------------------------------------------------------------
function StopEmergencyWithDelayTime(test_case_name, delay_time)	
	Test[test_case_name] = function(self)
		function to_run()
			self.hmiConnection:SendNotification("BasicCommunication.OnEventChanged", {isActive = false, eventName = "EMERGENCY_EVENT"})	
		end
		RUN_AFTER(to_run,delay_time)
	end	
end
---------------------------------------------------------------------------------------------
-- Checking application(s) is resumed unsuccessful if isActive parameter is invalid
-- @param test_case_name: main test name
---------------------------------------------------------------------------------------------
function CheckAppsResumptionUnsuccesslWhenIsActiveInvalid(test_case_name)		
	isActiveValue = {{isActive= "", eventName="EMERGENCY_EVENT"}, {isActive= 123, eventName="EMERGENCY_EVENT"}, {eventName="EMERGENCY_EVENT"}}
	invalid_type ={"IsActiveEmpty", "IsActiveWrongType", "IsActiveMissed"}
	for i=1, #isActiveValue do	
		Test[test_case_name .. invalid_type[i]] = function(self)				
			function to_run()
			self.hmiConnection:SendNotification("BasicCommunication.OnEventChanged", isActiveValue[i])	
			end
			RUN_AFTER(to_run,6000)
			EXPECT_HMICALL("BasicCommunication.ActivateApp"):Times(0)
		-- Resumption can't start
			self[mobile_session_name]:ExpectNotification("OnHMIStatus"):Times(0)
		end
	end
end
---------------------------------------------------------------------------------------------
-- Checking application(s) is resumed successful
-- @param test_case_name: main test name
-- @param expected_hmi_status: expected OnHMIStatus of each mobile session
---------------------------------------------------------------------------------------------
local function CheckAppsResumptionSuccessful(test_case_name, expected_hmi_status)	
	Test[test_case_name] = function(self) 
		local count_limited_apps = 0		
		-- Expected SDL sends BasicCommunication.ActivateApp for FULL application
		-- And SDL sends OnHMIStatus mobile applications		
		for k,v in pairs(expected_hmi_status) do 			
			if v.hmiLevel == "FULL" then
				EXPECT_HMICALL("BasicCommunication.ActivateApp")
				:Timeout(15000)
				:Do(function(_,data)			  
				  self.hmiConnection:SendResponse(data.id,"BasicCommunication.ActivateApp", "SUCCESS", {})
				end)
			else		
				count_limited_apps = count_limited_apps + 1
			end								
			self[tostring(k)]:ExpectNotification("OnHMIStatus", v)
			:Timeout(15000)
		end					
		-- Expected SDL sends BasicCommunication.OnResumeAudioSource for LIMITED applications
		EXPECT_HMINOTIFICATION("BasicCommunication.OnResumeAudioSource")
		:Times(count_limited_apps)	
	end
end
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Requirement summary: Resumption for single application (hmiLevel=FULL) is postponed in case UNEXPECTED_DISCONNECT and Emergency is active BEFORE application is connected
-- 1.Preconditions: 
-- -- 1.1. Application (NAVIGATION/COMMUNICATION/MEDIA/NON_MEDIA) is FULL
-- -- 1.2. Close session
-- 2.Steps: 
-- -- 2.1. Start Emergency 
-- -- 2.2. Register application
-- -- 2.3. Stop Emergency
-- 3.Expected Result: Resumption success when Emergency ended
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function CheckAppFullIsPostponedWhenEmergencyIsStartedBeforeRegisteredApp()
	for i=1, #apps do
		test_case_name = "TC_" .. tostring(tc_number)
		common_steps:AddNewTestCasesGroup("TC_" .. tostring(tc_number) ..
		"-HMILevel FULL: resumption for \"" .. apps[i].appName ..
		"\" app is postponed in case UNEXPECTED_DISCONNECT and Emergency is active BEFORE application is connected")
		-- Preconditions
		common_steps:RegisterApplication(test_case_name .. "_Register_App", mobile_session_name, apps[i])									 
		common_steps:ActivateApplication(test_case_name .. "_Activate_App", apps[i].appName)	
		common_steps:CloseMobileSession(test_case_name .. "_Close_Mobile_Session", mobile_session_name)					
		-- Body
		StartEmergency(test_case_name .. "_Start_Emergency")	
		common_steps:AddMobileSession(test_case_name .. "_Add_Mobile_Session", _, mobile_session_name)
		common_steps:RegisterApplication(test_case_name .. "_Register_App", mobile_session_name, apps[i])						
		audioStreamingState = (apps[i].appName == "NON_MEDIA") and "NOT_AUDIBLE" or "AUDIBLE"
		StopEmergencyWithDelayTime(test_case_name .. "_Stop_Emergency", 10000)
		CheckAppsResumptionUnsuccesslWhenIsActiveInvalid(test_case_name .. "_Resumption_SingleApp_Unsucess_When_IsActive_Invalid: ")				
		CheckAppsResumptionSuccessful(test_case_name .. "_Verify_Resumption_Success_When_Emergency_Ended",
		{mobileSession = {hmiLevel = "FULL", systemContext = "MAIN", audioStreamingState = audioStreamingState}})			
		--Post condition
		common_steps:UnregisterApp(test_case_name .. "_UnRegister_App", apps[i].appName)
		tc_number = tc_number + 1
		end
end
CheckAppFullIsPostponedWhenEmergencyIsStartedBeforeRegisteredApp()
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Requirement summary: Resumption for single application (hmiLevel=FULL) is postponed in case UNEXPECTED_DISCONNECT and Emergency is active AFTER application is connected
-- 1.Preconditions: 
-- -- 1.1. Application (NAVIGATION/COMMUNICATION/MEDIA/NON_MEDIA) is FULL
-- -- 1.2. Close session
-- 2.Steps:  
-- -- 2.1. Register application
-- -- 2.2. Start Emergency
-- -- 2.3. Stop Emergency
-- 3.Expected Result: Resumption success when Emergency ended
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function CheckAppFullIsPostponedWhenEmergencyIsStartedAfterRegisteredApp()
	for i=1, #apps do
		test_case_name = "TC_" .. tostring(tc_number)
		common_steps:AddNewTestCasesGroup("TC_" .. tostring(tc_number) ..
		"-HMILevel FULL: resumption for \"" .. apps[i].appName ..
		"\" app is postponed in case UNEXPECTED_DISCONNECT and Emergency is active AFTER application is connected")
		-- Preconditions
		common_steps:RegisterApplication(test_case_name .. "_Register_App", mobile_session_name, apps[i])									 
		common_steps:ActivateApplication(test_case_name .. "_Activate_App", apps[i].appName)	
		common_steps:CloseMobileSession(test_case_name .. "_Close_Mobile_Session", mobile_session_name)					
		-- Body		
		common_steps:AddMobileSession(test_case_name .. "_Add_Mobile_Session", _, mobile_session_name)
		common_steps:RegisterApplication(test_case_name .. "_Register_App", mobile_session_name, apps[i])						
		StartEmergency(test_case_name .. "_Start_Emergency")	
		StopEmergencyWithDelayTime(test_case_name .. "_Stop_Emergency", 10000)
		audioStreamingState = (apps[i].appName == "NON_MEDIA") and "NOT_AUDIBLE" or "AUDIBLE"
		CheckAppsResumptionUnsuccesslWhenIsActiveInvalid(test_case_name .. "_Resumption_SingleApp_Unsucess_When_IsActive_Invalid: ")		
		CheckAppsResumptionSuccessful(test_case_name .. "_Verify_Resumption_Success_When_Emergency_Ended",
		{mobileSession = {hmiLevel = "FULL", systemContext = "MAIN", audioStreamingState = audioStreamingState}})			
		--Post condition
		common_steps:UnregisterApp(test_case_name .. "_UnRegister_App", apps[i].appName)
		tc_number = tc_number + 1
		end
end
CheckAppFullIsPostponedWhenEmergencyIsStartedAfterRegisteredApp()
-- Stop and Start SDL again to avoid an ATF issue related to corID
common_steps:IgnitionOff("Ignition_Off")
common_steps:IgnitionOn("Ignition_On")
common_steps:AddMobileSession("Add_Session", _, mobile_session_name)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Requirement summary: Resumption for single application (hmiLevel=LIMITED) is postponed in case UNEXPECTED_DISCONNECT and Emergency is active BEFORE application is connected
-- 1.Preconditions: 
-- -- 1.1. Application (NAVIGATION/COMMUNICATION/MEDIA/NON_MEDIA) is LIMITED
-- -- 1.2. Close session
-- 2.Steps: 
-- -- 2.1. Start Emergency 
-- -- 2.2. Register application
-- -- 2.3. Stop Emergency
-- 3.Expected Result: Resumption success when Emergency ended
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function CheckAppLimitedIsPostponedWhenEmergencyIsStartedBeforerRegisteredApp()
	for i=1, #apps-1 do
		test_case_name = "TC_" .. tostring(tc_number)
		common_steps:AddNewTestCasesGroup("TC_" .. tostring(tc_number) ..
		"-HMILevel LIMITED: resumption for \"" .. apps[i].appName ..
		"\" app is postponed in case UNEXPECTED_DISCONNECT and Emergency is active BEFORE application is connected")		
		-- Preconditions
		common_steps:RegisterApplication(test_case_name .. "_Register_App", mobile_session_name, apps[i])									 
		common_steps:ActivateApplication(test_case_name .. "_Activate_App", apps[i].appName)	
		common_steps:ChangeHMIToLimited(test_case_name .. "_Change_App_To_Limited", apps[i].appName)
		common_steps:CloseMobileSession(test_case_name .. "_Close_Mobile_Session", mobile_session_name)					
		-- Body
		StartEmergency(test_case_name .. "_Start_Emergency")	
		common_steps:AddMobileSession(test_case_name .. "_Add_Mobile_Session", _, mobile_session_name)
		common_steps:RegisterApplication(test_case_name .. "_Register_App", mobile_session_name, apps[i])								
		StopEmergencyWithDelayTime(test_case_name .. "_Stop_Emergency", 10000)		
		CheckAppsResumptionUnsuccesslWhenIsActiveInvalid(test_case_name .. "_Resumption_SingleApp_Unsucess_When_IsActive_Invalid: ")		
		CheckAppsResumptionSuccessful(test_case_name .. "_Verify_Resumption_Success_When_Emergency_Ended",
		{mobileSession = {hmiLevel = "LIMITED", systemContext = "MAIN", audioStreamingState = "AUDIBLE"}})			
		--Post condition
		common_steps:UnregisterApp(test_case_name .. "_UnRegister_App", apps[i].appName)
		tc_number = tc_number + 1
		end
end
CheckAppLimitedIsPostponedWhenEmergencyIsStartedBeforerRegisteredApp()
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Requirement summary: Resumption for single application (hmiLevel=LIMITED) is postponed in case UNEXPECTED_DISCONNECT and Emergency is active AFTER application is connected
-- 1.Preconditions: 
-- -- 1.1. Application (NAVIGATION/COMMUNICATION/MEDIA/NON_MEDIA) is LIMITED
-- -- 1.2. Close session
-- 2.Steps: 
-- -- 2.1. Register application
-- -- 2.2. Start Emergency 
-- -- 2.3. Stop Emergency
-- 3.Expected Result: Resumption success when Emergency ended
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function CheckAppLimitedIsPostponedWhenEmergencyIsStartedAfterRegisteredApp()
	for i=1, #apps-1 do
		test_case_name = "TC_" .. tostring(tc_number)
		common_steps:AddNewTestCasesGroup("TC_" .. tostring(tc_number) ..
		"-HMILevel LIMITED: resumption for \"" .. apps[i].appName ..
		"\" app is postponed in case UNEXPECTED_DISCONNECT and Emergency is active BEFORE application is connected")
		-- Preconditions
		common_steps:RegisterApplication(test_case_name .. "_Register_App", mobile_session_name, apps[i])									 
		common_steps:ActivateApplication(test_case_name .. "_Activate_App", apps[i].appName)	
		common_steps:ChangeHMIToLimited(test_case_name .. "_Change_App_To_Limited", apps[i].appName)
		common_steps:CloseMobileSession(test_case_name .. "_Close_Mobile_Session", mobile_session_name)					
		-- Body
		common_steps:AddMobileSession(test_case_name .. "_Add_Mobile_Session", _, mobile_session_name)
		common_steps:RegisterApplication(test_case_name .. "_Register_App", mobile_session_name, apps[i])						
		StartEmergency(test_case_name .. "_Start_Emergency")			
		StopEmergencyWithDelayTime(test_case_name .. "_Stop_Emergency", 10000)
		CheckAppsResumptionUnsuccesslWhenIsActiveInvalid(test_case_name .. "_Resumption_SingleApp_Unsucess_When_IsActive_Invalid: ")		
		CheckAppsResumptionSuccessful(test_case_name .. "_Verify_Resumption_Success_When_Emergency_Ended",
		{mobileSession = {hmiLevel = "LIMITED", systemContext = "MAIN", audioStreamingState = "AUDIBLE"}})			
		--Post condition
		common_steps:UnregisterApp(test_case_name .. "_UnRegister_App", apps[i].appName)
		tc_number = tc_number + 1
		end
end
CheckAppLimitedIsPostponedWhenEmergencyIsStartedAfterRegisteredApp()
-------------------------------------------Postcondition-------------------------------------
common_steps:RestoreIniFile("Restore_Ini_file")
