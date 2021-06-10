# hexrays-docset

A command-line utillity to generate a Dash Docset for the HexRays decompiler.

This project is extremely rough around the edges. I wrote it in a hurry. PRs to polish it up are welcome!

## Usage

```bash
hexrays-docset <path-to-docset-bundle>
```

## First steps

1. Follow [this guide](https://kapeli.com/docsets) to create the `.docset` bundle. Use the `Info.plist` in the root of this repository as the `Info.plist` for your docset.
2. Open a terminal and `cd` into the `Resources` folder of your docset
3. Run the following command to download the documentation for offline use:
   ```bash
   wget -m -k -p -L -np -nd -nH -D hex-rays.com https://hex-rays.com/products/decompiler/manual/sdk/index.shtml
   ```
   There should be no subfolders inside `Resources`.
4. Run this utility, passing in the path to your docset.
5. If you wish to adjust the web pages at all, do that now. See [Adjustments](#adjustments) below.
6. Put your docset wherever you want then double click it to add it to Dash. Dash will not copy or move it for you.

## Adjustments
Open `Resources/index.shtml` in a browser. You may want to adjust the CSS and remove some annoying tags.   
I removed the following tags:
- `<header>`
- `<div id="header-top">`
- `<div id="sales">`

You will need to use something like VS Code or `sed` to find and remove the entire contents of each tag. If you end up removing these tags, you will need to adjust some CSS too. As for that, the `wget` command I used did not download some CSS files, at the expense of only downloading the documentation files and not the entire website. I couldn't figure out how to make it download any CSS file but only `shtml` files under `/sdk/`. Anyway, I found that I wanted most of the CSS offline. So you will need to manually download these three files, throw them into `Resources`, and do a find-and-replace to replace their respsective URLs in every file with their filenames alone. i.e. `https://use.typekit.net/mhw5sar.css` → `mhw5sar.css`
- https://use.typekit.net/mhw5sar.css
- https://hex-rays.com/wp-content/themes/hx2021/dist/css/style.min.css
- https://hex-rays.com/wp-content/themes/hx2021/dist/css/uicons-regular-rounded/css/uicons-regular-rounded.css

Then, you can adjust the CSS to replace the massive `margin-top: 160px;` with `margin-top: 0px;` for `#main`.
