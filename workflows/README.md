# Random examples of workflows

The workflows listed here are meant for one-time demonstration of selected features.

## Dynamic steps
Shows how wizard steps on the Orchestrator workflow execution page can be dynamically shown/hidden to the user.

The workflow schema requires following demo HTTP server running:
```
yarn install
yarn start
```

Make sure the Backstage's proxy is properly configured to forward requests
from `$${{backend.baseUrl}}/api/proxy/mytesthttpserver` to `localhost:12345`.


