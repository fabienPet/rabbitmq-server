@echo off
REM  The contents of this file are subject to the Mozilla Public License
REM  Version 1.1 (the "License"); you may not use this file except in
REM  compliance with the License. You may obtain a copy of the License
REM  at http://www.mozilla.org/MPL/
REM
REM  Software distributed under the License is distributed on an "AS IS"
REM  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
REM  the License for the specific language governing rights and
REM  limitations under the License.
REM
REM  The Original Code is RabbitMQ.
REM
REM  The Initial Developer of the Original Code is GoPivotal, Inc.
REM  Copyright (c) 2007-2015 Pivotal Software, Inc.  All rights reserved.
REM

setlocal

rem Preserve values that might contain exclamation marks before
rem enabling delayed expansion
set TN0=%~n0
set TDP0=%~dp0
set CONF_SCRIPT_DIR="%~dp0"
set P1=%1
setlocal enabledelayedexpansion

REM Get default settings with user overrides for (RABBITMQ_)<var_name>
REM Non-empty defaults should be set in rabbitmq-env
call "%TDP0%\rabbitmq-env.bat" %~n0

set STARVAR=
shift
:loop1
if "%1"=="" goto after_loop
	set STARVAR=%STARVAR% %1
	shift
goto loop1
:after_loop

if "!ERLANG_SERVICE_MANAGER_PATH!"=="" (
    if not exist "!ERLANG_HOME!\bin\erl.exe" (
        echo.
        echo ******************************
        echo ERLANG_HOME not set correctly.
        echo ******************************
        echo.
        echo Please either set ERLANG_HOME to point to your Erlang installation or place the
        echo RabbitMQ server distribution in the Erlang lib folder.
        echo.
        exit /B
    )
    for /f "delims=" %%i in ('dir /ad/b "!ERLANG_HOME!"') do if exist "!ERLANG_HOME!\%%i\bin\erlsrv.exe" (
        set ERLANG_SERVICE_MANAGER_PATH=!ERLANG_HOME!\%%i\bin
    )
)

set CONSOLE_FLAG=
set CONSOLE_LOG_VALID=
for %%i in (new reuse) do if "%%i" == "!RABBITMQ_CONSOLE_LOG!" set CONSOLE_LOG_VALID=TRUE
if "!CONSOLE_LOG_VALID!" == "TRUE" (
    set CONSOLE_FLAG=-debugtype !RABBITMQ_CONSOLE_LOG!
)

rem *** End of configuration ***

if not exist "!ERLANG_SERVICE_MANAGER_PATH!\erlsrv.exe" (
    echo.
    echo **********************************************
    echo ERLANG_SERVICE_MANAGER_PATH not set correctly.
    echo **********************************************
    echo.
    echo "!ERLANG_SERVICE_MANAGER_PATH!\erlsrv.exe" not found
    echo Please set ERLANG_SERVICE_MANAGER_PATH to the folder containing "erlsrv.exe".
    echo.
    exit /B 1
)

if "!P1!" == "install" goto INSTALL_SERVICE
for %%i in (start stop disable enable list remove) do if "%%i" == "!P1!" goto MODIFY_SERVICE

echo.
echo *********************
echo Service control usage
echo *********************
echo.
echo !TN0! help    - Display this help
echo !TN0! install - Install the !RABBITMQ_SERVICENAME! service
echo !TN0! remove  - Remove the !RABBITMQ_SERVICENAME! service
echo.
echo The following actions can also be accomplished by using
echo Windows Services Management Console (services.msc):
echo.
echo !TN0! start   - Start the !RABBITMQ_SERVICENAME! service
echo !TN0! stop    - Stop the !RABBITMQ_SERVICENAME! service
echo !TN0! disable - Disable the !RABBITMQ_SERVICENAME! service
echo !TN0! enable  - Enable the !RABBITMQ_SERVICENAME! service
echo.
exit /B


:INSTALL_SERVICE

if not exist "!RABBITMQ_BASE!" (
    echo Creating base directory !RABBITMQ_BASE! & md "!RABBITMQ_BASE!"
)

set ENV_OK=true
CALL :check_not_empty "RABBITMQ_BOOT_MODULE" !RABBITMQ_BOOT_MODULE!
CALL :check_not_empty "RABBITMQ_NAME_TYPE" !RABBITMQ_NAME_TYPE!
CALL :check_not_empty "RABBITMQ_NODENAME" !RABBITMQ_NODENAME!


if "!ENV_OK!"=="false" (
    EXIT /b 78
)

"!ERLANG_SERVICE_MANAGER_PATH!\erlsrv" list !RABBITMQ_SERVICENAME! 2>NUL 1>NUL
if errorlevel 1 (
    "!ERLANG_SERVICE_MANAGER_PATH!\erlsrv" add !RABBITMQ_SERVICENAME! -internalservicename !RABBITMQ_SERVICENAME!
) else (
    echo !RABBITMQ_SERVICENAME! service is already present - only updating service parameters
)

set RABBITMQ_EBIN_ROOT=!RABBITMQ_HOME!\ebin

CALL :get_noex !RABBITMQ_ADVANCED_CONFIG_FILE! RABBITMQ_ADVANCED_CONFIG_FILE_NOEX

if "!RABBITMQ_ADVANCED_CONFIG_FILE!" == "!RABBITMQ_ADVANCED_CONFIG_FILE_NOEX!.config" (
    set RABBITMQ_ADVANCED_CONFIG_FILE=!RABBITMQ_ADVANCED_CONFIG_FILE_NOEX!
)

"!ERLANG_HOME!\bin\erl.exe" ^
        -pa "!RABBITMQ_EBIN_ROOT!" ^
        -noinput -hidden ^
        -s rabbit_prelaunch ^
        -conf_advanced "!RABBITMQ_ADVANCED_CONFIG_FILE!" ^
        -rabbit enabled_plugins_file "!RABBITMQ_ENABLED_PLUGINS_FILE!" ^
        -rabbit plugins_dir "!$RABBITMQ_PLUGINS_DIR!" ^
        !RABBITMQ_NAME_TYPE! rabbitmqprelaunch!RANDOM!!TIME:~9!

if ERRORLEVEL 3 (
    rem ERRORLEVEL means (or greater) so we need to catch all other failure
    rem cases here
    exit /B 1
) else if ERRORLEVEL 2 (
    rem dist port mentioned in config, do not attempt to set it
) else if ERRORLEVEL 1 (
    exit /B 1
) else (
    set RABBITMQ_DIST_ARG=-kernel inet_dist_listen_min !RABBITMQ_DIST_PORT! -kernel inet_dist_listen_max !RABBITMQ_DIST_PORT!
)

if not exist "!RABBITMQ_SCHEMA_DIR!" (
    mkdir "!RABBITMQ_SCHEMA_DIR!"
)

if not exist "!RABBITMQ_SCHEMA_DIR!\rabbitmq.schema" (
    copy "!RABBITMQ_HOME!\priv\schema\rabbitmq.schema" "!RABBITMQ_SCHEMA_DIR!\rabbitmq.schema"
)
    REM Try to create advanced config file, if it doesn't exist
    REM It still can fail to be created, but at least not for default install
if not exist "!RABBITMQ_ADVANCED_CONFIG_FILE!.config" (
    echo []. > !RABBITMQ_ADVANCED_CONFIG_FILE!.config
)

CALL :get_noex !RABBITMQ_CONFIG_FILE! RABBITMQ_CONFIG_FILE_NOEX

if "!RABBITMQ_CONFIG_FILE!" == "!RABBITMQ_CONFIG_FILE_NOEX!.config" (
    if exist "!RABBITMQ_CONFIG_FILE!" (
        set RABBITMQ_CONFIG_ARG=-config "!RABBITMQ_CONFIG_FILE_NOEX!"
    )
) else if "!RABBITMQ_CONFIG_FILE!" == "!RABBITMQ_CONFIG_FILE_NOEX!.conf" (
    set RABBITMQ_CONFIG_ARG=-conf "!RABBITMQ_CONFIG_FILE_NOEX!" ^
                            -conf_dir !RABBITMQ_GENERATED_CONFIG_DIR! ^
                            -conf_script_dir !CONF_SCRIPT_DIR:\=/! ^
                            -conf_schema_dir !RABBITMQ_SCHEMA_DIR!
    if exist "!RABBITMQ_ADVANCED_CONFIG_FILE!.config" (
        set RABBITMQ_CONFIG_ARG=!RABBITMQ_CONFIG_ARG! ^
                                -conf_advanced "!RABBITMQ_ADVANCED_CONFIG_FILE!" ^
                                -config "!RABBITMQ_ADVANCED_CONFIG_FILE!"
    )
) else (
    if exist "!RABBITMQ_CONFIG_FILE!.config" (
        set RABBITMQ_CONFIG_ARG=-config "!RABBITMQ_CONFIG_FILE!"
    ) else (
        rem Always specify generated config arguments, we cannot
        rem assume .conf file is available
        set RABBITMQ_CONFIG_ARG=-conf "!RABBITMQ_CONFIG_FILE!" ^
                                -conf_dir !RABBITMQ_GENERATED_CONFIG_DIR! ^
                                -conf_script_dir !CONF_SCRIPT_DIR:\=/! ^
                                -conf_schema_dir !RABBITMQ_SCHEMA_DIR!
        if exist "!RABBITMQ_ADVANCED_CONFIG_FILE!.config" (
            set RABBITMQ_CONFIG_ARG=!RABBITMQ_CONFIG_ARG! ^
                                    -conf_advanced "!RABBITMQ_ADVANCED_CONFIG_FILE!" ^
                                    -config "!RABBITMQ_ADVANCED_CONFIG_FILE!"
        )
    )
)


set RABBITMQ_LISTEN_ARG=
if not "!RABBITMQ_NODE_IP_ADDRESS!"=="" (
   if not "!RABBITMQ_NODE_PORT!"=="" (
      set RABBITMQ_LISTEN_ARG=-rabbit tcp_listeners "[{\"!RABBITMQ_NODE_IP_ADDRESS!\", !RABBITMQ_NODE_PORT!}]"
   )
)

if "!RABBITMQ_LOGS!" == "-" (
    set RABBIT_LAGER_HANDLER=tty
) else (
    set RABBIT_LAGER_HANDLER=\""!RABBITMQ_LOGS:\=/!"\"
)

set RABBITMQ_START_RABBIT=
if "!RABBITMQ_NODE_ONLY!"=="" (
    set RABBITMQ_START_RABBIT=-s "!RABBITMQ_BOOT_MODULE!" boot
)

if "!RABBITMQ_IO_THREAD_POOL_SIZE!"=="" (
    set RABBITMQ_IO_THREAD_POOL_SIZE=64
)

if "!RABBITMQ_SERVICE_RESTART!"=="" (
    set RABBITMQ_SERVICE_RESTART=restart
)

set ERLANG_SERVICE_ARGUMENTS= ^
-pa "!RABBITMQ_EBIN_ROOT!" ^
-boot start_sasl ^
!RABBITMQ_START_RABBIT! ^
!RABBITMQ_CONFIG_ARG! ^
+W w ^
+A "!RABBITMQ_IO_THREAD_POOL_SIZE!" ^
+P 1048576 ^
!RABBITMQ_LISTEN_ARG! ^
!RABBITMQ_SERVER_ERL_ARGS! ^
-kernel inet_default_connect_options "[{nodelay,true}]" ^
!RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS! ^
-sasl errlog_type error ^
-sasl sasl_error_logger false ^
-rabbit lager_log_root \""!RABBITMQ_LOG_BASE:\=/!"\" ^
-rabbit lager_handler !RABBIT_LAGER_HANDLER! ^
-rabbit enabled_plugins_file \""!RABBITMQ_ENABLED_PLUGINS_FILE:\=/!"\" ^
-rabbit plugins_dir \""!RABBITMQ_PLUGINS_DIR:\=/!"\" ^
-rabbit plugins_expand_dir \""!RABBITMQ_PLUGINS_EXPAND_DIR:\=/!"\" ^
-rabbit windows_service_config \""!RABBITMQ_CONFIG_FILE:\=/!"\" ^
-os_mon start_cpu_sup false ^
-os_mon start_disksup false ^
-os_mon start_memsup false ^
-mnesia dir \""!RABBITMQ_MNESIA_DIR:\=/!"\" ^
!RABBITMQ_SERVER_START_ARGS! ^
!RABBITMQ_DIST_ARG! ^
!STARVAR!

set ERLANG_SERVICE_ARGUMENTS=!ERLANG_SERVICE_ARGUMENTS:\=\\!
set ERLANG_SERVICE_ARGUMENTS=!ERLANG_SERVICE_ARGUMENTS:"=\"!



"!ERLANG_SERVICE_MANAGER_PATH!\erlsrv" set !RABBITMQ_SERVICENAME! ^
-onfail !RABBITMQ_SERVICE_RESTART! ^
-machine "!ERLANG_SERVICE_MANAGER_PATH!\erl.exe" ^
-env ERL_CRASH_DUMP="!RABBITMQ_BASE:\=/!/erl_crash.dump" ^
-env ERL_LIBS="!ERL_LIBS!" ^
-workdir "!RABBITMQ_BASE!" ^
-stopaction "rabbit:stop_and_halt()." ^
!RABBITMQ_NAME_TYPE! !RABBITMQ_NODENAME! ^
!CONSOLE_FLAG! ^
-comment "Multi-protocol open source messaging broker" ^
-args "!ERLANG_SERVICE_ARGUMENTS!" > NUL

goto END


:MODIFY_SERVICE

"!ERLANG_SERVICE_MANAGER_PATH!\erlsrv" !P1! !RABBITMQ_SERVICENAME!
goto END


:END

EXIT /B 0

:check_not_empty
if "%~2"=="" (
    ECHO "Error: ENV variable should be defined: %1. Please check rabbitmq-env, rabbitmq-default, and !RABBITMQ_CONF_ENV_FILE! script files. Check also your Environment Variables settings"
    set ENV_OK=false
    EXIT /B 78
    )
EXIT /B 0

:get_noex
set "%~2=%~dpn1"
EXIT /B 0

endlocal
endlocal
