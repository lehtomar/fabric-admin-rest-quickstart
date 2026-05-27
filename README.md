# Power BI / Fabric Admin REST API – Setup &amp; Examples

A small, focused toolkit for calling the **Power BI / Fabric Admin REST API**
either as a signed-in user (delegated, via `az login`) or as a service principal.

Includes:
- a token helper that supports both auth modes,
- a robust REST wrapper that surfaces the (hidden) `X-PowerBI-Error-Info` header,
- a **diagnostic** script that pinpoints which permission layer is broken
  (token / basic API / read-admin / update-admin),
- a **demo** script that calls five admin endpoints and prints both the
  results and a summary of every URL it called,
- a stand-alone **HTML setup guide** (`setup-guide.html`) you can open locally
  or host as a static page.

> **Bottom line:** the most common reason admin *read* calls work but admin
> *update/write* calls fail with **401 / 404** is **not code** — it's the
> tenant-level authorization model. There are now **two separate tenant
> toggles** (read-only vs. updates) and both need to be scoped to the
> security group your service principal belongs to.

---

## 1. How service principal access to the Admin APIs works

A service principal (SP) calling `/admin/...` endpoints needs **all four** of
these to line up:

| # | Layer | What it is | Where |
|---|---|---|---|
| 1 | **Entra app + SP** | App registration with **no admin-consent Power BI permissions** added (they cause errors) | Entra ID → App registrations |
| 2 | **Security group** | Microsoft Entra security group, SP added as a **direct member** | Entra ID → Groups |
| 3a | **Tenant setting (read)** | *"Service principals can access **read-only** admin APIs"* → *Specific security groups* → the group | Fabric Admin portal → Tenant settings → **Admin API settings** |
| 3b | **Tenant setting (update)** | *"Service principals can access admin APIs used for **updates**"* → *Specific security groups* → the group | Same place |
| 4 | **Token** | OAuth2 **client credentials** flow against `https://analysis.windows.net/powerbi/api/.default` | Your script |

Sources:
[Allow SPs to use read-only admin APIs](https://learn.microsoft.com/power-bi/enterprise/read-only-apis-service-principal-authentication),
[Fabric Admin portal – Admin API settings](https://learn.microsoft.com/fabric/admin/service-admin-portal-admin-api-settings).

### Common failure pattern (read ✅, update ❌)

Only toggle **3a** is on. Toggle **3b** ("…admin APIs used for **updates**")
is either off or the SP's group isn't added to it. This is the most common
gotcha and shows up as **401 (token has no admin-write rights)** or **404
(Power BI returns 404 for unauthorized admin endpoints instead of 403)**.

### Don'ts (common traps)

- ❌ Do **not** add Power BI delegated/application API permissions to the app
  registration with admin consent — the docs explicitly warn that this causes
  hard-to-troubleshoot errors. The SP gets its rights from the tenant setting
  + security group, not from Graph-style permissions.
- ❌ Do **not** use a **nested** group — only direct members of the group
  named in the tenant setting are honored.
- ❌ Do **not** assume the *Fabric administrator* Entra role gives an SP
  admin-API access; the SP still needs to be in the allowed group.
- ❌ The SP must **not** be a guest / B2B account.

---

## 2. User credentials — the easiest path

If you don't actually need unattended automation, **skip the SP setup
entirely**. A user account with the **Fabric administrator** (or legacy
*Power BI administrator*) Entra role can call every admin endpoint with no
tenant toggles, no security group, and no app registration.

Requirements:

- Azure CLI installed and signed in: `az login --tenant <tenant-id>`
- Signed-in user has the **Fabric administrator** role
  (assign it in Entra admin center → *Roles and administrators* →
  *Fabric administrator*).
- If the role is PIM-eligible it must be **activated**, then sign out and
  back in so the token picks it up.

---

## 3. Required tenant settings (SP mode only)

In **Fabric Admin portal → Tenant settings**:

**Developer settings**

- ✅ *Allow service principals to use Power BI APIs* → *Specific security
  groups* → add e.g. `sg-powerbi-admin-api`

**Admin API settings**

- ✅ *Service principals can access read-only admin APIs* → *Specific
  security groups* → same group
- ✅ *Service principals can access admin APIs used for updates* →
  *Specific security groups* → same group  ← the one that's usually missed
- (Optional, for scanner API) *Enhance admin APIs responses with detailed
  metadata* and *…with DAX and mashup expressions*

Save and **wait ~15 minutes** for propagation before retrying.

---

## 4. Quick start

### User mode (recommended)

```powershell
az login --tenant <tenant-id>
cd examples
.\Test-AdminApiAccess.ps1                       # diagnoses access
.\Demo-AdminApiCalls.ps1 -Top 5                 # calls 5 admin APIs and prints a summary
```

### Service principal mode

```powershell
cd examples
.\Test-AdminApiAccess.ps1 -Mode SP `
    -TenantId     <tenant-id> `
    -ClientId     <app-client-id> `
    -ClientSecret <secret> `
    -TestWorkspaceId <workspace-guid>
```

You can also run `.\Setup-SecurityGroup.ps1 -AppClientId <id>` to create
the Entra security group and add the SP to it via Microsoft Graph.

---

## 5. Files

| File | Purpose |
|---|---|
| `examples/Get-PbiAdminToken.ps1` | Acquire access token (User via `az` or SP via client-credentials) |
| `examples/Invoke-PbiAdminApi.ps1` | REST wrapper that surfaces `X-PowerBI-Error-Info` and the error body |
| `examples/Test-AdminApiAccess.ps1` | Probes 4 layers in order; tells you exactly which one is broken |
| `examples/Demo-AdminApiCalls.ps1` | Calls Groups / Datasets / Reports / Capacities / ActivityEvents and prints a summary |
| `examples/Update-WorkspaceUser-Example.ps1` | End-to-end example of a write call (`POST /admin/groups/{id}/users`) |
| `examples/Setup-SecurityGroup.ps1` | Idempotently creates the Entra SG and adds the SP via Microsoft Graph |
| `setup-guide.html` | Self-contained, copy/paste-friendly HTML setup guide |

---

## 6. License

MIT — see [LICENSE](LICENSE).
