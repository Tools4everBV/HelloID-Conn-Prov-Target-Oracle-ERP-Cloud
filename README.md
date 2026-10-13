# HelloID-Conn-Prov-Target-Oracle-ERP-Cloud

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible for acquiring the connection details, such as the username, password, and certificate. You might need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Oracle-ERP-Cloud](#helloid-conn-prov-target-oracle-erp-cloud)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [Shared API Credentials](#shared-api-credentials)
    - [SCIM User Response Conversion](#scim-user-response-conversion)
    - [User Update Payload](#user-update-payload)
    - [Employee Linkage and Management](#employee-linkage-and-management)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Oracle-ERP-Cloud_ is a _target_ connector. _Oracle-ERP-Cloud_ provides a set of REST APIs that allow you to programmatically interact with its data.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks |
| ----------------------------------------- | --------- | --------------------------------------- | ------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable, Delete |         |
| **Permissions**                           | ✅         | Retrieve, Grant, Revoke                 |         |
| **Resources**                             | ❌         | -                                       |         |
| **Entitlement Import: Accounts**          | ✅         | -                                       |         |
| **Entitlement Import: Permissions**       | ✅         | -                                       |         |
| **Governance Reconciliation Resolutions** | ✅         | -                                       |         |


## Getting started

### HelloID Icon URL
URL of the icon used for the HelloID Provisioning target system.
```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Oracle-ERP-Cloud/refs/heads/main/Icon.png
```

### Requirements

- **Username**: Obtain a username with permission to access the API.
- **Password**: Obtain a password with permission to access the API.
- **API URL**: Confirm the base URL for the tenant, for example `https://<tenant>.oraclecloud.com`.

### Connection settings

The following settings are required to connect to the API.

| Setting  | Description                        | Mandatory |
| -------- | ---------------------------------- | --------- |
| UserName | The UserName to connect to the API | Yes       |
| Password | The Password to connect to the API | Yes       |
| BaseUrl  | The URL to the API                 | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Oracle-ERP-Cloud_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `ExternalId`                      |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the property `id` property from _Oracle-ERP-Cloud_

## Remarks

### Shared API Credentials
- **Single Credential Set**: The configured username and password are used to authenticate requests to both the SCIM endpoints and the REST endpoints. No separate credential set is required for either API.

### SCIM User Response Conversion
- **Account Object Conversion**: The user endpoints use the SCIM standard for their response bodies. The connector uses `ConvertTo-HelloIDAccountObject` to convert each SCIM response into the account object format expected by HelloID, ensuring that imported account data matches the configured HelloID account fields.

### User Update Payload
- Unlike the generic SCIM connector on GitHub, user updates do not use the SCIM PatchOp request body (`Operations`). The Oracle API does not accept that payload for user updates; it expects a partial User resource in the PATCH request instead.

### Employee Linkage and Management
- **Employee Relationship**: Each user must be linked to an existing employee record before the user can be used successfully in Oracle ERP Cloud. Employee records, including their creation and maintenance, are managed directly in AFAS and are not created or updated by this connector. If the required employee link is missing, user provisioning will not complete successfully.

- **Person Number Matching**: During account creation, the connector matches the HelloID person’s `ExternalId` with the Oracle employee `PersonNumber`. The connector makes an additional API request to a different non-SCIM endpoint to resolve the employee before creating the user. Exactly one matching employee with a valid `PersonId` is required.

- **API Version Segment**: The `11.13.18.05` part in the REST endpoints appears to be a version or release identifier for the Oracle ERP Cloud API. In practice, The latest alias is also supported and can be used as a shorthand when specifying an exact API version is unnecessary. However, API updates or changes introduced by the supplier may affect connector compatibility and behavior, potentially requiring adjustments to the connector.


## Development resources

### API endpoints

The following endpoints are used by the connector:

| Endpoint                                                                                              | HTTP Method        | Description                                                  |
| ----------------------------------------------------------------------------------------------------- | ------------------ | ------------------------------------------------------------ |
| `/hcmRestApi/scim/Users?filter={correlationField} eq {correlationValue}`                              | GET                | Find an existing user during account correlation.            |
| `/hcmRestApi/scim/Users`                                                                              | POST               | Create a user account.                                       |
| `/hcmRestApi/scim/Users/{accountReference}`                                                           | GET, PATCH, DELETE | Retrieve, update, enable, disable, or delete a user account. |
| `/hcmRestApi/scim/Users?startIndex={startIndex}&count={pageSize}`                                     | GET                | Import users with pagination.                                |
| `/hcmRestApi/scim/Roles?startIndex={startIndex}&count={pageSize}`                                     | GET                | Retrieve and import permissions with pagination.             |
| `/hcmRestApi/scim/Roles/{permissionReference}`                                                        | PATCH              | Grant or revoke a permission for a user.                     |
| `/hcmRestApi/resources/11.13.18.05/workers?q=PersonNumber={externalId}&fields=PersonId&onlyData=true` | GET                | Extra non-SCIM request to find the Oracle employee associated with a HelloID person. |
| `/hcmRestApi/resources/11.13.18.05/userAccounts/{userId}`                                             | PATCH              | Extra non-SCIM request to link the user account to the Oracle employee.                |

### API documentation

For more information on the Oracle ERP Cloud API, please refer to the [Oracle ERP Cloud API documentation](https://docs.oracle.com/en/cloud/saas/applications-common/26a/farca/api-users.html).

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
