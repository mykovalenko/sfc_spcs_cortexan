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
USE ROLE IDENTIFIER($DEPLOY_ROLE_OWNER);
USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($DEPLOY_SCHEMA);
USE WAREHOUSE IDENTIFIER($SERVICE_RUN_VWHS);

-- this is where you upload and store your semantic models (yaml files)
CREATE STAGE IF NOT EXISTS SEMANTICS
    ENCRYPTION = (TYPE='SNOWFLAKE_SSE') 
    DIRECTORY = (ENABLE = TRUE);

PUT 'file://res/*.yaml' @SEMANTICS AUTO_COMPRESS = FALSE; 

-- stage for some sample data and tables that support this demo app
CREATE OR REPLACE STAGE IMPORT
    DIRECTORY = (ENABLE = TRUE);

PUT 'file://res/*.csv' @IMPORT AUTO_COMPRESS = FALSE;

CREATE OR REPLACE TABLE DAILY_REVENUE (
    DATE DATE,
    REVENUE FLOAT,
    COGS FLOAT,
    FORECASTED_REVENUE FLOAT
);

COPY INTO DAILY_REVENUE
FROM @IMPORT
FILES = ('daily_revenue_combined.csv')
FILE_FORMAT = (
    TYPE=CSV,
    SKIP_HEADER=2,
    FIELD_DELIMITER=',',
    TRIM_SPACE=FALSE,
    FIELD_OPTIONALLY_ENCLOSED_BY=NONE,
    REPLACE_INVALID_CHARACTERS=TRUE,
    DATE_FORMAT=AUTO,
    TIME_FORMAT=AUTO,
    TIMESTAMP_FORMAT=AUTO
    EMPTY_FIELD_AS_NULL = FALSE
    error_on_column_count_mismatch=false
)
ON_ERROR=CONTINUE
FORCE = TRUE ;

CREATE OR REPLACE TABLE DAILY_REVENUE_BY_PRODUCT (
    DATE DATE,
    PRODUCT_LINE VARCHAR(16777216),
    REVENUE FLOAT,
    COGS FLOAT,
    FORECASTED_REVENUE FLOAT
);

COPY INTO DAILY_REVENUE_BY_PRODUCT
FROM @IMPORT
FILES = ('daily_revenue_by_product_combined.csv')
FILE_FORMAT = (
    TYPE=CSV,
    SKIP_HEADER=1,
    FIELD_DELIMITER=',',
    TRIM_SPACE=FALSE,
    FIELD_OPTIONALLY_ENCLOSED_BY=NONE,
    REPLACE_INVALID_CHARACTERS=TRUE,
    DATE_FORMAT=AUTO,
    TIME_FORMAT=AUTO,
    TIMESTAMP_FORMAT=AUTO
    EMPTY_FIELD_AS_NULL = FALSE
    error_on_column_count_mismatch=false
)
ON_ERROR=CONTINUE
FORCE = TRUE ;

CREATE OR REPLACE TABLE DAILY_REVENUE_BY_REGION (
    DATE DATE,
    SALES_REGION VARCHAR(16777216),
    REVENUE FLOAT,
    COGS FLOAT,
    FORECASTED_REVENUE FLOAT
);

COPY INTO DAILY_REVENUE_BY_REGION
FROM @IMPORT
FILES = ('daily_revenue_by_region_combined.csv')
FILE_FORMAT = (
    TYPE=CSV,
    SKIP_HEADER=1,
    FIELD_DELIMITER=',',
    TRIM_SPACE=FALSE,
    FIELD_OPTIONALLY_ENCLOSED_BY=NONE,
    REPLACE_INVALID_CHARACTERS=TRUE,
    DATE_FORMAT=AUTO,
    TIME_FORMAT=AUTO,
    TIMESTAMP_FORMAT=AUTO
    EMPTY_FIELD_AS_NULL = FALSE
    error_on_column_count_mismatch=false
)
ON_ERROR=CONTINUE
FORCE = TRUE;

CREATE OR REPLACE PROCEDURE CA_BROKER(filepath VARCHAR, prompt VARCHAR)
    RETURNS STRING
    LANGUAGE PYTHON
    RUNTIME_VERSION = 3.11
    PACKAGES = ('snowflake-snowpark-python')
    HANDLER = 'run'
AS $$
import json
import _snowflake

def run(filepath: str, prompt: str) -> dict:
    request_body = {
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": prompt
                    }
                ]
            }
        ],
        "semantic_model_file": f"{filepath}",
    }
    resp = _snowflake.send_snow_api_request(
        "POST",
        f"/api/v2/cortex/analyst/message",
        {},
        {},
        request_body,
        {},
        30000,
    )
    if resp["status"] < 400:
        return resp["content"]
    else:
        raise Exception(
            f"Failed request with status {resp['status']}: {resp}"
        )        
$$;
