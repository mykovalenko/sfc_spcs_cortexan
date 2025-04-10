import os
import json
import streamlit as st
import snowflake.connector
from snowflake.snowpark import Session
from typing import Dict, List, Optional
import helpers

DEP_DBS = os.getenv('DEP_DBS')
DEP_XMA = os.getenv('DEP_XMA')
DEP_STG = os.getenv('DEP_STG')

# Get User from SPCS Headers
try:
    user = st.context.headers["Sf-Context-Current-User"] or Visitor
except KeyError:
    user = "Visitor"

#https://streamlit-emoji-shortcodes-streamlit-app-gwckff.streamlit.app/
st.set_page_config(page_title = f'Snowy [{user}]', page_icon = ':lollipop:', layout = 'wide')



@st.cache_resource
def get_snowflake_session():
    return helpers.session()



@st.cache_data()
def load_available_sms():
    get_snowflake_session().sql(f"LIST @{DEP_DBS}.{DEP_XMA}.{DEP_STG} PATTERN='.*.yaml'").collect();
    p_df = get_snowflake_session().sql(f"select \"name\" from TABLE(RESULT_SCAN(LAST_QUERY_ID())) order by 1").to_pandas()
    return p_df



def process_message(prompt: str, model: str) -> None:
    """Processes a message and adds the response to the chat."""
    st.session_state.messages.append(
        {"role": "user", "content": [{"type": "text", "text": prompt}]}
    )
    with st.chat_message("user"):
        st.markdown(prompt)
    with st.chat_message("assistant"):
        with st.spinner("Generating response..."):
            response = get_snowflake_session().sql(f"CALL CA_BROKER('@{DEP_DBS}.{DEP_XMA}.{model}', '{prompt}')").collect();
            for r in response:
                jr = json.loads(r.CA_BROKER)
                request_id = jr["request_id"]
                content = jr["message"]["content"]
                display_content(content=content, request_id=request_id)  # type: ignore[arg-type]
                st.session_state.messages.append(
                    {"role": "assistant", "content": content, "request_id": request_id}
                )



def display_content(
    content: List[Dict[str, str]],
    request_id: Optional[str] = None,
    message_index: Optional[int] = None,
) -> None:
    """Displays a content item for a message."""
    message_index = message_index or len(st.session_state.messages)
    if request_id:
        with st.expander("Request ID", expanded=False):
            st.markdown(request_id)
    for item in content:
        if item["type"] == "text":
            st.markdown(item["text"])
        elif item["type"] == "suggestions":
            with st.expander("Suggestions", expanded=True):
                for suggestion_index, suggestion in enumerate(item["suggestions"]):
                    if st.button(suggestion, key=f"{message_index}_{suggestion_index}"):
                        st.session_state.active_suggestion = suggestion
        elif item["type"] == "sql":
            with st.expander("SQL Query", expanded=False):
                st.code(item["statement"], language="sql")
            with st.expander("Results", expanded=True):
                with st.spinner("Running SQL..."):
                    #df = pd.read_sql(item["statement"], get_snowflake_connection())
                    df = get_snowflake_session().sql(item["statement"]).to_pandas()
                    if len(df.index) > 1:
                        data_tab, line_tab, bar_tab = st.tabs(
                            ["Data", "Line Chart", "Bar Chart"]
                        )
                        data_tab.dataframe(df)
                        if len(df.columns) > 1:
                            df = df.set_index(df.columns[0])
                        with line_tab:
                            st.line_chart(df)
                        with bar_tab:
                            st.bar_chart(df)
                    else:
                        st.dataframe(df)





with st.sidebar:
    st.title(f"Cortex Analyst")
    st.header(f"", divider='rainbow')
    s_sms = st.selectbox(label='Semantic Models', options=load_available_sms())

if "messages" not in st.session_state:
    st.session_state.messages = []
    st.session_state.suggestions = []
    st.session_state.active_suggestion = None

for message_index, message in enumerate(st.session_state.messages):
    with st.chat_message(message["role"]):
        display_content(
            content=message["content"],
            request_id=message.get("request_id"),
            message_index=message_index,
        )

if user_input := st.chat_input("What is your question?"):
    process_message(prompt=user_input, model=s_sms)

if st.session_state.active_suggestion:
    process_message(prompt=st.session_state.active_suggestion, model=s_sms)
    st.session_state.active_suggestion = None
