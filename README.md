# rc_admin_menu

A modular, admin-only toolkit for ESX Legacy with a custom NUI panel. Features
are built as self-contained **modules** so new tools can be added without
touching the existing ones. The first module is a **Weapon Spawner**.

- **Framework:** ESX Legacy (`es_extended`)
- **UI / utils:** `ox_lib` (callbacks, notifications, keybind)
- **Inventory:** `ox_inventory` (weapons, ammo and attachments are items)

---

## Opening the panel

- Command: `/adminmenu`
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
Config.AdminGroups    = { 'admin', 'developer' }
Config.ElevatedGroups = { 'admin', 'developer' }
```

---

## Weapon Spawner

1. Pick a **target**: Myself · Player ID · Nearby (elevated) · Everyone (elevated).
2. Choose the **Weapons**, **Ammo** or **Armor** tab, search / filter by category.
3. Click an item to open the give dialog:
   - **Weapons** — quantity, ammo (skipped for melee/throwables), durability,
     and optional attachments (multi-select).
   - **Ammo** — amount of the selected ammo item.
   - **Armor** — quantity of the selected body-armour item.

The catalog is built automatically from the **ox_inventory item registry**, so
it always reflects the weapons/ammo/attachments/armor your server actually has.
Items are classified by name prefix:

```lua
weaponPrefixes    = { 'weapon_' }
ammoPrefixes      = { 'ammo' }
componentPrefixes = { 'component', 'at_' }
armorPrefixes     = { 'armour', 'armor', 'kevlar' }
```

If a list comes up empty in-game, adjust these prefixes to match your item
names. Weapons that take no ammo are listed in `Config.WeaponSpawner.noAmmoWeapons`.

> Attachments are written to the weapon's `metadata.components`. ox_inventory
> ignores any component that isn't valid for that weapon.

Item images are pulled from ox_inventory (`nui://ox_inventory/web/images/<item>.png`,
honouring a custom `client.image`). If an image is missing the thumbnail simply
falls back to an empty slot — add the image to `ox_inventory/web/images` to fix it.

Limits (quantity, ammo, durability, nearby radius) are enforced server-side via
`Config.WeaponSpawner.limits`.

---

## Money Manager

1. Pick a **target** (Myself · Player ID · Nearby · Everyone — the last two are
   elevated-only, same as every module).
2. Click an **account** (Cash, Bank, Black Money by default).
3. Choose an **operation** and amount:
   - **Add** — add to the balance.
   - **Remove** — subtract from the balance (capped at the current balance, so
     it never goes negative).
   - **Set** — set the balance to an exact value.

Accounts, the allowed operations, and the amount clamp are configured in
`Config.MoneySetter`:

```lua
Config.MoneySetter = {
    accounts   = { { name = 'money', label = 'Cash' }, { name = 'bank', label = 'Bank' }, ... },
    operations = { 'add', 'remove', 'set' },
    limits     = { amount = { min = 1, max = 10000000 } },  -- 'set' allows 0
}
```

Amounts are validated and clamped **server-side** before any ESX account call,
and — like weapon grants — every change is logged (`Config.Logging`).

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

   Add any actions as `lib.callback.register('rc_admin_menu:...')` and guard them
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
