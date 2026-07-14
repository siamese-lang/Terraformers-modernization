# Runtime Check Output Template

```text
$ curl -i http://localhost:8080/actuator/health
HTTP/1.1 200
...

$ curl -i http://localhost:8080/internal/runtime/required-config
HTTP/1.1 200
[
  {"name":"SPRING_DATASOURCE_URL","present":true},
  {"name":"SPRING_DATASOURCE_PASSWORD","present":true}
]
```

Do not include actual secret values. The runtime check should only expose key names and boolean presence.
