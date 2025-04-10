SET TARGET_DATABASE   = '<% dbsname %>';
SET DEPLOY_SCHEMA     = '<% depname %>';
SET DEPLOY_ROLE_OWNER = 'APP_<% depname %>_OWNER';
SET APP_ROLE_TYPE_01  = 'APP_<% depname %>_ROL01';
SET APP_ROLE_TYPE_02  = 'APP_<% depname %>_ROL02';
SET APP_NB_CONTROL    = 'APP_<% depname %>_CONTROL';
SET SERVICE_NAME      = 'APP_<% depname %>_SVC';
SET SERVICE_RUN_USER  = 'APP_<% depname %>_USER';
SET SERVICE_RUN_POOL  = 'APP_<% depname %>_POOL';
SET SERVICE_RUN_VWHS  = 'APP_<% depname %>_WH';
SET EXT_ACC_INT_NAME  = 'APP_<% depname %>_EXASINT';
SET EXT_ACC_NET_RULE  = 'APP_<% depname %>_NETRULE';


---------------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_EU';

CREATE OR REPLACE ROLE IDENTIFIER($DEPLOY_ROLE_OWNER);
CREATE OR REPLACE ROLE IDENTIFIER($APP_ROLE_TYPE_01);

CREATE OR REPLACE USER IDENTIFIER($SERVICE_RUN_USER)
    TYPE = SERVICE
    DEFAULT_ROLE = $DEPLOY_ROLE_OWNER
;--RSA_PUBLIC_KEY = ''; --generated and setup at deplyment time

GRANT DATABASE ROLE SNOWFLAKE.COPILOT_USER TO ROLE IDENTIFIER($APP_ROLE_TYPE_01);

GRANT EXECUTE TASK ON ACCOUNT TO ROLE IDENTIFIER($DEPLOY_ROLE_OWNER);
GRANT MONITOR USAGE ON ACCOUNT TO ROLE IDENTIFIER($DEPLOY_ROLE_OWNER);
GRANT BIND SERVICE ENDPOINT ON ACCOUNT TO ROLE IDENTIFIER($DEPLOY_ROLE_OWNER);

GRANT ROLE IDENTIFIER($DEPLOY_ROLE_OWNER) TO USER IDENTIFIER($SERVICE_RUN_USER);
GRANT ROLE IDENTIFIER($APP_ROLE_TYPE_01) TO ROLE IDENTIFIER($DEPLOY_ROLE_OWNER);
GRANT ROLE IDENTIFIER($DEPLOY_ROLE_OWNER) TO ROLE SYSADMIN;


---------------------------------------------------------------------------------
USE ROLE SYSADMIN;
USE SECONDARY ROLES IDENTIFIER($DEPLOY_ROLE_OWNER);

CREATE DATABASE IF NOT EXISTS IDENTIFIER($TARGET_DATABASE);
GRANT USAGE ON DATABASE IDENTIFIER($TARGET_DATABASE) TO ROLE IDENTIFIER($DEPLOY_ROLE_OWNER);
GRANT CREATE SCHEMA ON DATABASE IDENTIFIER($TARGET_DATABASE) TO ROLE IDENTIFIER($DEPLOY_ROLE_OWNER);

CREATE WAREHOUSE IF NOT EXISTS IDENTIFIER($SERVICE_RUN_VWHS)
  WAREHOUSE_SIZE = 'small'
  WAREHOUSE_TYPE = 'standard'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;
GRANT ALL PRIVILEGES ON WAREHOUSE IDENTIFIER($SERVICE_RUN_VWHS) TO ROLE IDENTIFIER($DEPLOY_ROLE_OWNER);
GRANT OWNERSHIP ON WAREHOUSE IDENTIFIER($SERVICE_RUN_VWHS) TO ROLE IDENTIFIER($DEPLOY_ROLE_OWNER) REVOKE CURRENT GRANTS;

CREATE COMPUTE POOL IF NOT EXISTS IDENTIFIER($SERVICE_RUN_POOL)
    MIN_NODES = 1
    MAX_NODES = 1
    AUTO_RESUME = TRUE
    AUTO_SUSPEND_SECS = 300
    INSTANCE_FAMILY = CPU_X64_XS;
GRANT ALL PRIVILEGES ON COMPUTE POOL IDENTIFIER($SERVICE_RUN_POOL) TO ROLE IDENTIFIER($DEPLOY_ROLE_OWNER);
GRANT OWNERSHIP ON COMPUTE POOL IDENTIFIER($SERVICE_RUN_POOL) TO ROLE IDENTIFIER($DEPLOY_ROLE_OWNER) REVOKE CURRENT GRANTS;



---------------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
USE DATABASE IDENTIFIER($TARGET_DATABASE);

CREATE NETWORK RULE IF NOT EXISTS IDENTIFIER($EXT_ACC_NET_RULE)
  TYPE = 'HOST_PORT'
  MODE = 'EGRESS'
  VALUE_LIST = ('0.0.0.0:443', '0.0.0.0:80');
  --remove 0.0.0.0 if not required

CREATE EXTERNAL ACCESS INTEGRATION IF NOT EXISTS IDENTIFIER($EXT_ACC_INT_NAME)
  ALLOWED_NETWORK_RULES = ($EXT_ACC_NET_RULE)
  ENABLED = TRUE;

GRANT USAGE ON INTEGRATION IDENTIFIER($EXT_ACC_INT_NAME) TO ROLE IDENTIFIER($DEPLOY_ROLE_OWNER);



---------------------------------------------------------------------------------
USE ROLE IDENTIFIER($DEPLOY_ROLE_OWNER);
USE DATABASE IDENTIFIER($TARGET_DATABASE);

CREATE SCHEMA IF NOT EXISTS IDENTIFIER($DEPLOY_SCHEMA) WITH MANAGED ACCESS;
USE SCHEMA IDENTIFIER($DEPLOY_SCHEMA);

-- this is for container service specifications (yaml). We can also supply it directly in sql statement
CREATE STAGE IF NOT EXISTS SPECS
    ENCRYPTION = (TYPE='SNOWFLAKE_SSE')
    DIRECTORY = (ENABLE = TRUE);

-- this volume is mounted on a container in case something requires longtime storage that survives the restarts.
-- We store the app code there so when changes are needed you don't have to rebuild the whole container and just
-- can upload the app tar and recreate the service from sql
CREATE STAGE IF NOT EXISTS VOLUMES
    ENCRYPTION = (TYPE='SNOWFLAKE_SSE') 
    DIRECTORY = (ENABLE = TRUE);

-- this is repo for docker image of the app
CREATE IMAGE REPOSITORY IF NOT EXISTS IMAGES;

-- this stage is for app control scripts and notebooks
CREATE STAGE IF NOT EXISTS CONTROL
    ENCRYPTION = (TYPE='SNOWFLAKE_SSE')
    DIRECTORY = (ENABLE = TRUE);

PUT file://dbs/control.ipynb @CONTROL AUTO_COMPRESS=FALSE OVERWRITE=TRUE; 

CREATE OR REPLACE NOTEBOOK IDENTIFIER($APP_NB_CONTROL)
    FROM @CONTROL
    QUERY_WAREHOUSE = $SERVICE_RUN_VWHS
    MAIN_FILE = 'control.ipynb';
