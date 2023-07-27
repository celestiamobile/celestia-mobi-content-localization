# Localization for celestia.mobi

There are two types of localization in this repository.

## String Based Localization

For example: `addon-title` folder includes localization for titles for add-ons.

If the language you want to support is not in the folder yet. Create a folder for your language (for example, create `ja.lproj` folder for Japanese, and then create a file named `Localizable.strings` in `ja.lproj` folder). Look in `en.lproj/Localizable.strings` for the entries you want to localize, copy the entries to your `Localizable.strings` and translate.

If the language you want to support is already in the folder. Open `Localizable.strings` directly in that folder, there should be a comment on each string that tells you the English word this entry. Localize the string and remove the leading `//` for the translated line.

## HTML Based Localization

For example: `addon-rich-description` folder includes localization for rich descriptions for add-ons.

In the folder find the page you want to translate. The folder names in `addon-rich-description` are the IDs for add-ons. The folder names in `guide-content` are the IDs for articles.

```
https://celestia.mobi/resources/item?item=87D5FBAB-5722-70A9-6D4C-F4FD22EA87BC
https://celestia.mobi/resources/guide?guide=211275CC-D79A-9C81-A2DF-6047DD4AC35D
```

The above example's add-on ID is `87D5FBAB-5722-70A9-6D4C-F4FD22EA87BC`. The article page's ID is `211275CC-D79A-9C81-A2DF-6047DD4AC35D`.

In the folder of the page you want to localize. If the page is not translated into your language yet, there will only be an `en` folder inside it. Copy the folder and rename it to the language you want to localize (for example, `ja` for Japanese). Open the folder, translate the content in `data.html`. After you finish translating, open `id.txt` and change the content to a new random UUID (you can generate one here: https://guidgenerator.com/online-guid-generator.aspx).

If the page is already translated in your language (the language folder exists), and you just want to make some changes, only make changes to `data.html`.
