# rc_admin

A modular, admin-only toolkit for ESX Legacy with a custom NUI panel. Features
are built as self-contained **modules** so new tools can be added without
touching the existing ones. The first module is a **Weapon Spawner**.

- **Framework:** ESX Legacy (`es_extended`)
- **UI / utils:** `ox_lib` (callbacks, notifications, keybind)
- **Inventory:** `ox_inventory` (weapons, ammo and attachments are items)

---

## Opening the panel

- Command: `/admin`
- Optional keybind: set `Config.OpenKey` (e.g. `'F6'`); players can rebind it
  under **Settings → Key Bindings → FiveM**.

Access is checked **server-side** against the ESX `users.group` on every open
and every action — the client never decides who is an admin.

---

## Permissions

| Group set            | What it unlocks                                              |
|----------------------|-------------------------------------------------------------|
| `Config.AdminGroups` | Open the panel; give to **yourself** or a **player by ID**. |
| `Config.ElevatedGroups` | Additionally: give to **everyone online** and **nearby** players. |

Defaults (edit in `config.lua`):

```lua
Config.AdminGroups    = { 'owner', 'developer', 'admin', 'superadmin' }
Config.ElevatedGroups = { 'owner', 'developer', 'superadmin' }
```

---

## Weapon Spawner

1. Pick a **target**: Myself · Player ID · Nearby (elevated) · Everyone (elevated).
2. Choose the **Weapons** or **Ammo** tab, search / filter by category.
3. Click an item to open the give dialog:
   - **Weapons** — quantity, ammo (skipped for melee/throwables), durability,
     and optional attachments (multi-select).
   - **Ammo** — amount of the selected ammo item.

The catalog is built automatically from the **ox_inventory item registry**, so
it always reflects the weapons/ammo/attachments your server actually has. Items
are classified by name prefix:

```lua
weaponPrefixes    = { 'weapon_' }
ammoPrefixes      = { 'ammo' }
componentPrefixes = { 'component', 'at_' }
```

If a list comes up empty in-game, adjust these prefixes to match your item
names. Weapons that take no ammo are listed in `Config.WeaponSpawner.noAmmoWeapons`.

> Attachments are written to the weapon's `metadata.components`. ox_inventory
> ignores any component that isn't valid for that weapon.

Limits (quantity, ammo, durability, nearby radius) are enforced server-side via
`Config.WeaponSpawner.limits`.

---

## Logging

Every grant is recorded (`Config.Logging`):

- `console = true` prints to the server console.
- Set `webhook` to a Discord webhook URL to also log there.

---

## Adding a new module later

1. **Server** — create `server/modules/<name>.lua` and register it:

   ```lua
   Admin.registerModule({
       id    = 'my_feature',          -- must match the NUI renderer key
       label = 'My Feature',
       icon  = '🛠',
       elevated = false,              -- true = ElevatedGroups only
       getContext = function(src) return { ... } end,  -- data sent to the NUI
   })
   ```

   Add any actions as `lib.callback.register('rc_admin:...')` and guard them
   with `Admin.isAdmin(src)` / `Admin.isElevated(src)`.

2. **Client** — create `client/modules/<name>.lua` with `RegisterNUICallback`s
   that forward to your server callbacks.

3. **NUI** — add a renderer in `html/script.js`:

   ```js
   RENDERERS.my_feature = function (root, mod) { /* build the UI */ };
   ```

4. Register all three files in `fxmanifest.lua` (core files load first).

The sidebar nav, permission filtering and panel shell are handled by the core.
```
