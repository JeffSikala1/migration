curl -i -H "Authorization: Bearer $TOKEN" \
     -H "Accept: text/x-yaml, */*" \
     "https://${HOST}/rest/api/latest/plan/CAM-CAD/specs?format=YAML" | head -20
# Expect: HTTP/1.1 200 OK and a YAML-looking body (no login/seraph XML)

# 1) JSON page of plans (should be HTTP/200 + application/json)
curl -si -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" \
  "https://${HOST}/rest/api/latest/plan?max-results=2&start-index=0" | head

# 2) One known plan’s YAML (should be HTTP/200 and start with 'version:')
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://${HOST}/rest/api/latest/plan/AV-AVUP/specs?format=YAML" | head

# 3) Deployment list (should be HTTP/200 + JSON)
curl -si -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" \
  "https://${HOST}/rest/api/latest/deploy/project/all" | head