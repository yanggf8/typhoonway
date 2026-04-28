# HLD Diagrams

The `.mmd` files are the source of truth for `HLD.html` diagrams. Rendered SVGs live in `diagrams/svg/` and are referenced from the HTML.

Render all diagrams:

```sh
sh diagrams/render.sh
```

The script uses a local `mmdc` if available; otherwise it runs the pinned Mermaid CLI package through:

```sh
npx -y @mermaid-js/mermaid-cli@10.9.1
```
