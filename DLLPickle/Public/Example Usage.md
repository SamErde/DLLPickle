# Example Usage to Build Out

## At module import or in functions that need MSAL

`$MsalAssembly = Add-MsalAssembly`

## Use MSAL types (they'll work even after unload is called, until GC runs)

`$ClientApp = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($ClientId).Build()`

## When done (maybe in module removal or cleanup)

`Remove-MsalAssembly`
