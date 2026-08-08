# Welcome to RouzMe

## What Is This Thing?

Who doesn't have a painfully long list in their lives? Whether it's Likes in a music app, or lists of to-do's, books to read or movies to watch, the sheer length of a list can be overwhelming.

But help is here! RouzMe moves you to actually do stuff. Use RouzMe to help you organize and track the ideas, goals, and interests you've had nagging at you.

Think of it as a way to keep track of all those things you say "I've been meaning to…" about.

The app helps you:

- Keep your Ideas organized into collections (Pursuits), with notes reminding you where they came from and/or why they're here;
- Link your Ideas to external resources like movies, books, music, and more;
- Get a random (more or less) suggestion when you're ready to act;
- Track what you've accomplished;
- Get ideas from others and share yours.

## Compiling Pursuits

Pursuits are the main way to organize your ideas. Each pursuit represents a type of activity or interest.

Examples of Pursuits:

- "Watch a Movie"
- "Read a Book"
- "Try a Restaurant"
- "Learn a Skill"
- "Visit a Place"

Within each pursuit, you add individual Ideas — the specific things you want to do. For example, in "Watch a Movie", you might add "The Godfather", "Blade Runner", or "Spirited Away".

You can share your Pursuits with others, or keep them private for your eyes only.

## Linking Elsewhere

You can add links pointing to external resources for your Ideas. This makes it easy to jump directly to relevant content.

Supported link types:

- Streaming services (Netflix, Amazon Prime, Apple TV+, etc.)
- Music services (Spotify, Apple Music, YouTube Music, Tidal)
- Websites and articles
- Any other URL you want to save

When you add a link, the app will try to automatically fetch information like titles and descriptions. For some services (like movies and music), it can even find where content is available to stream.

**Pro tip:** Just paste a URL into the headline when adding a new Idea, and the app will handle the rest!

## Take Shares from other apps

Perfect for recording ideas for articles to read, videos to watch, recordings to play, or anything else you come across in the wild world online. Once you send something to RouzMe, it will help you keep it as an Idea.

"Sending something" is a little different if you're on mobile (phone, pad) or in a browser. 
On mobile, you use the device's Share feature. Most apps will have this icon somewhere: {{share-icon}}. Tap that to start the process, then find and tap the RouzMe icon.

In a browser, the "Send to RouzMe" browser extension does the same from any web page.
Get the extension for Chrome [here](https://chromewebstore.google.com/detail/send-to-rouzme/ngimiedpjjenmdblfdpceghkgiamgnkj), which will land the RouzMe icon ({{rouzme-icon}}) to the right of the address bar:

![The RouzMe extension button next to the browser address bar](help-extension.png)

Either way, RouzMe will start a new Idea from the shared material. 
Then you can edit the Idea to suit (change the title, add a note reminding you why it's there,
choose the pursuit to keep it under...), then hit Create to save it for posterity.

## Import a whole collection of Ideas

Already have a list of things you've been meaning to do? You can import them in bulk from other sources.

How to import:

1. On the Home screen, select the pursuit you want to add to, or start a new one.
2. Hit the "Add an Idea" button, then choose "Add a List of Ideas".
3. Paste the list into the text box, or hit the Import button and select a data source file to upload.
4. The app will process your data and add the Ideas individually to the Pursuit.

Supported import formats:

- Plain text files in a variety of formats (see Example Formats below)
- JSON files (one item per line)
- CSV files (spreadsheets exported from Excel, Google Sheets, etc.)
- Letterboxd (for movie watchlists)
- JustWatch (for streaming content)
- Other structured data formats

This is perfect if you're migrating from another app or have been keeping lists in spreadsheets. Import hundreds of items at once instead of entering them one by one!

**Example Formats**

Plain text (a bare URL on a line has its title fetched automatically):

```
Movie Title 1
Movie Title 2
https://www.justwatch.com/us/movie/inception
```

JSON (one item per line):

```
{"title": "Inception", "link": "https://www.justwatch.com/us/movie/inception"}
{"title": "The Matrix", "link": "https://www.justwatch.com/us/movie/the-matrix"}
```

JSON array:

```
[{"title": "Inception"}, {"title": "The Matrix", "link": "https://www.justwatch.com/us/movie/the-matrix"}]
```

Markdown links:

```
[Inception](https://example.com/inception)
[The Matrix](https://example.com/matrix)
```

HTML links:

```
<a href="https://www.justwatch.com/us/movie/inception">Inception</a>
<a href="https://www.justwatch.com/us/movie/the-matrix">The Matrix</a>
```

## Share a Pursuit with a friend

If you want to share your accumulated wisdom, you can let anyone see (but not change!) any of your Pursuits. Here's how:

1. On the Home screen, pick the Pursuit you want to share.
2. In the menu (top right), choose "Share this Pursuit". (Pro tip: the adjacent "Share Any Pursuit(s)" lets you send them in bulk.)
3. To select which Ideas will be visible to the recipient, tap the pencil icon.
4a. On mobile, tap the Share button ({{share-icon}}), then either Copy Link or choose another app (e.g., an email app) to share through.
4b. In a browser, you'll have to Copy Link directly and paste it into a message to your friend with flowery words about how great RouzMe is. When they tap that link, they'll land in RouzMe and be offered the shared pursuit(s). 

PS: To manage your shares, both incoming and outgoing, hit the "Shared With Me" item on the main menu (top right).

## Ideas for Using RouzMe

{{ideas-for-using}}
