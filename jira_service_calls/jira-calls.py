"""
Python calls to JIRA REST API
JQL Searches and return results
"""
import json
from jira import JIRA

jira_server = "https://jira.corp.phishme.com"
user_id = 'Jeff.Koors@cofense.com'
user_pass = 'HeartlyLaci0720!'
options = {'server' : jira_server}
# for auth and pass, will need to create secrets, env var or something secure in AWS
# I validated the response and auth via a successful search in CLI
jira = JIRA(options, basic_auth=(user_id, user_pass))

sprint_results = jira.search_issues('sprint=1275')
print(sprint_results)
