/*
 * Copyright Red Hat, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

const express = require('express');

const app = express();
app.disable('x-powered-by');

const port = 12345;
app.use(express.json());

const logRequest = req => {
  // eslint-disable-next-line no-console
  console.log('request: ', {
    originalUrl: req.originalUrl,
    method: req.method,
    query: req.query,
    headers: req.headers,
    body: req.body,
  });
};

app.get('/', (_, res) => {
  res.send(
    'Hello World from HTTP test server providing endpoints for the "Dynamic steps" workflow',
  );
});

app.post('/customschema', (req, res) => {
  logRequest(req);

  const stepOneField = req.body?.stepOneField;
  const stepThreeField = req.body?.stepThreeField;

  const mySchemaUpdater = {
    "type": "string",
    "title": "Not shown to the user",
    "ui:widget": "SchemaUpdater",
    "ui:props": {
      "fetch:url": "$${{backend.baseUrl}}/api/proxy/mytesthttpserver/customschema",
      "fetch:method": "POST",
      "fetch:body": {
        // This drives the change on the stepThree to show stepFive
        "stepThreeField": "$${{current.stepThree.stepThreeField}}",
        // But provide everything to keep the /customschema stateless (aka pure function)
        "stepOneField": "$${{current.stepOne.stepOneField}}",
      },
      "fetch:response:value": "mydataroot",
      "fetch:retrigger": [
        "current.stepOne.stepOneField",
        "current.stepThree.stepThreeField"
      ]
    }
  }

  const stepThree = {
    "type": "object",
    "properties": {
      "stepThreeField": {
        "type": "string",
        "title": "Step three field"
      },
      "stepThreeSchemaUpdater": mySchemaUpdater
    }
  };
  const stepFour = {
    "type": "object",
    "properties": {
      "stepFourField": {
        "type": "string",
        "title": "Step four field"
      }
    }
  };
  const stepFive = {
    "type": "object",
    "properties": {
      "stepFiveField": {
        "type": "string",
        "title": "Step five field"
      }
    }
  };

  const response = {
    mydataroot: {
      stepTwo: {
        "type": "object",
        "properties": {
          "stepTwoField": {
            "type": "string",
            "title": "Step two field"
          },
          "addedStepTwoField": {
            "type": "string",
            "title": "Added step two field"
          }
        }
      },
      "stepThree": {
        "type": "object",
        "ui:widget": "hidden",
        "properties": {}
      },
      "stepFour": {
        "type": "object",
        "ui:widget": "hidden",
        "properties": {}
      },
      "stepFive": {
        "type": "object",
        "ui:widget": "hidden",
        "properties": {}
      },
    },
  };

  if (stepOneField === 'three') {
    response.mydataroot.stepThree = stepThree;
  }

  if (stepOneField === 'threeFour') {
    response.mydataroot.stepThree = stepThree;
    response.mydataroot.stepFour = stepFour;
  }

  if (stepThreeField === 'five') {
    response.mydataroot.stepFive = stepFive;
  }

  if (stepOneField === 'remove_two') {
    response.mydataroot.stepTwo = {
      "type": "object",
      "ui:widget": "hidden",
      "properties": {}
    }
  }

  // HTTP 200
  res.send(JSON.stringify(response));
});

app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.info(
    `Simple HTTP server for orchestrator-form-widgets development only. Provides endpoints for the "Dynamic course select" example workflow. Listening on ${port} port.`,
  );
});
