# Mobile Dev Helper

One command to run your app locally **and** open it on your phone.

## Quick start

```bash
npm run mobile
```

That will:

1. Install dependencies if needed
2. Build and serve the app locally
3. Create a public phone URL (via localtunnel)
4. Print the link to open on your mobile

## Options

```bash
npm run mobile -- --hot          # Live reload (dev server)
npm run mobile -- --port 3000    # Custom port
npm run mobile -- --no-install   # Skip npm install
npm run mobile -- --help         # Show help
```

## Supported projects

| Project | Auto-detected by | Default port |
|---|---|---|
| Angular | `angular.json` | 4200 (hot) / 8080 (stable) |
| Vite / React | `vite.config.*` | 5173 |
| Create React App | `react-scripts` in `package.json` | 3000 |
| Next.js | `next` in `package.json` | 3000 |
| Other Node.js | `npm run dev` or `npm start` | 8080 |

## Use in other projects

Copy `scripts/mobile-dev.sh` into any project and add this to `package.json`:

```json
"mobile": "bash scripts/mobile-dev.sh"
```

Then run `npm run mobile` from that project.

## Phone tunnel password

If `loca.lt` asks for a password:

1. On your phone, search **"what is my ip"**
2. Enter that IP on the tunnel page
3. Tap **Continue**

## Recommended mode

- **`npm run mobile`** (stable) — best for phone testing; fewer tunnel errors
- **`npm run mobile -- --hot`** — live reload while coding on desktop + phone
