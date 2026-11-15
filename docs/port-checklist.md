# The port checklist

Each iPad view file (kiff/tafs `ios/Tafs/Views`, at the pin in `shared.pin`) against its
state on this Mac. A file is **ported** when every branch it draws is on this Mac, **partial**
when part of it is (what's missing is named), **not started**, or **not for macOS 12** (and
why). It's judged from `main`'s code and docs, not from pull requests still in review. The PR
that ports a file updates its line here.

Paths under "Mac" are in `Sources/App` unless they start with `Core/` (`Sources/Core`).

## Ported

| iPad file | Lines | What | Models | Mac |
| :- | -: | :- | :- | :- |
| ExportChatsView.swift | 82 | Account › Export my chats | AppModel.exportChats | `account/ExportChatsView.swift`, `Core/account/ChatsExport.swift` |
| PairSignInView.swift | 104 | Signing in from another phone: this device shows the pairing QR and its check code, the phone approves | KIFF/Pairing | "Add this Mac with a phone": `pairing/SignInView.swift`, `SignInModel.swift`, `QRCode.swift`, `Core/pairing/Client.swift`, `Messages.swift` |
| ReportAnswerSheet.swift | 124 | Report an answer Coach or a taf wrote | AnswerReport | `coach/ReportAnswerSheet.swift`, `Core/coach/Report.swift` |
| YourStepCard.swift | 46 | A step a taf handed its owner, with Done and Skip | YourStep | `approvals/NeedsYou.swift`, `Core/approvals/YourStep.swift` (signed with the device key after Touch ID or the Mac's password) |

## Partial

| iPad file | Lines | What | Mac has | Missing |
| :- | -: | :- | :- | :- |
| AIConsentView.swift | 74 | The AI-data consent, and Account's AI use row | Coach's consent sheet: the words, Allow, Not now (`coach/CoachView.swift`, `Core/contracts/AIConsent.swift`) | `AIConsentRow` (Account › AI use) |
| AccountPreferencesView.swift | 37 | Account's theme and time zone pickers | `ThemePicker`: Light, Dark, System, kept across launches (`account/AccountView.swift`) | `TimeZonePicker` |
| ApprovalSetupView.swift | 102 | This device's approval readiness: `ReadinessReader`, `ApprovalGate`, `ApprovalNotice`, `ApprovalNotReady` | `ApprovalNotReady`'s line where an approval can't be made here (`approvals/NeedsYou.swift`, `taf/HaltView.swift`) | `ReadinessReader`, `ApprovalGate`, `ApprovalNotice`: no Mac approves yet |
| CalendarView.swift | 434 | Calendar: the month card, Day, Week, Month | All three views, the month card, the agenda, today in the account's zone (`calendar/CalendarView.swift`, `Core/calendar/Agenda.swift`) | Opening a taf from an event |
| CoachMode.swift | 131 | Coach mode over the app: `CoachView`, `CoachPanel`, `PhoneCoachPanel` | Coach as a screen of the window, with its title and New conversation (`coach/CoachView.swift`) | Coach mode over the app and over a taf's page: the panel, the dimmed ground, Back, a tap outside. `PhoneCoachPanel` is the phone's |
| ConnectAppsView.swift | 1141 | Connect apps, a connected app's detail, connecting's approval | The search, Yours and Discover, the table (`ConnectColumns`), each row's end, logos, More apps, Not listed? Ask Coach (`connections/ConnectAppsView.swift`, `Core/connections/Apps.swift`) | Connecting and Sign in again from here, `ConnectApprovalSheet`, `AppConnectionsView`, `ConnectionDetailView`, Disconnect (each with its approval) |
| CreditsViews.swift | 181 | The credits the account's tafs used, and one taf's runs | `CreditsPanel`: both periods, each taf's line, Coach, not counted, the note (`usage/UsageView.swift`, `Core/usage/Usage.swift`) | `TafCreditsView` and `CreditsRunRow` (a taf's runs behind its line) |
| DevicesView.swift | 69 | Account › Devices | The list, every row's sheet, This device, this Mac's own Sign out (`account/Devices.swift`, `Core/account/Account.swift`) | Signing another device out, which becomes the iPad's signed approval (`prepareRemoveDevice`, `signApproval`) first |
| HaltScreen.swift | 176 | A halt of one taf or every taf | Halt now and Halt all now, the parts that hold it, following while halting (`taf/HaltView.swift`, `Core/taf/Halt.swift`) | Resume, which gives authority back and is signed |
| HomeRecipes.swift | 242 | Home with no taf: the recipes | `HomeRecipes`, `OwnWordsRow`, `RecipeRow`, `AppMarks`, `RecipeSheet` (`overview/HomeRecipesView.swift`, `Core/overview/Recipes.swift`) | Handing a recipe to a new Coach conversation; the apps' logos |
| HomeSplitView.swift | 584 | The sidebar for the whole app and what it opens | The brand, the screens with Needs you's count, NEEDS YOU's held calls, YOUR TAFS with each taf's line, Start a new taf, Coach, Account (`shell/ShellView.swift`, `shell/SignedInView.swift`, `Core/shell/Screen.swift`, `HeldRow.swift`) | Shared with you; Other agents; tafs being set up and Discard; the recipes strip and Explore; + New's gallery; the Unreachable and Plan lines at the foot |
| HomeView.swift | 403 | Home: the tafs, what needs the person, no taf's recipes | The Overview's list, NEEDS YOU, each taf's Now, Card and Last result, the no-taf branch (`overview/OverviewView.swift`, `Core/overview/Home.swift`, `LastResult.swift`) | Reading the list again by itself; Own words opening a new conversation (`startNewTaf`) |
| NeedsYouView.swift | 603 | Needs you: held calls, "Did this happen?", steps, Coach's waits, knocks, alerts | Held calls (`HeldCallCard`'s face and countdown) with Refuse; "Did this happen?" without its Yes or No; Your step; Card unit requests; the empty state (`approvals/NeedsYou.swift`, `Core/approvals/HeldCalls.swift`, `Unproven.swift`) | Approve once and Extra room; next steps; Allow from now on; Refuse's Touch ID or password confirmation; `CoachWaitingCard`, `AlertsCard`, `SetAllAsideButton`; knocks |
| NotificationSettingsView.swift | 138 | Account › Alerts | What an alert looks like (`LockScreenAlert`), Alerts on this Mac, Sound, kept per account (`account/AlertsView.swift`, `approvals/Notifier.swift`, `Core/approvals/AlertPrefs.swift`) | `AlertingTafsView` (which tafs alert); alerts with tafs closed, which need a signed build |
| OnboardingView.swift | 63 | The welcome: what tafs is, Sign in with KIFF, Try it with sample data | The welcome and Sign in with KIFF (`pairing/SignInView.swift`) | Try it with sample data |
| PeopleViews.swift | 291 | People and groups | The groups and the people, read every 20 seconds, in the iPad's order (`account/PeopleView.swift`, `Core/account/People.swift`) | Making, renaming or deleting a group and changing its people (each signed) |
| RecordSearchViews.swift | 192 | The Record's search | The search as the person pauses, its pages on More, `RecordHitRow`, `RecordCaseSheet` (`record/RecordView.swift`, `Core/record/Record.swift`) | A case's steps as `SourceActivityRow`, with each step's next step |
| RecordView.swift | 689 | The Record, its rows, filters and receipts | The list, the taf chips, the filters, days and rows, paging (`record/RecordView.swift`, `Core/record/Record.swift`) | A day's spend; a day's reads folded into one line; exporting receipts; a taf's detail |
| SetupChatView.swift | 1957 | Coach's conversation | The thread, the answer as it's written, cards answered, Decline, the AI-data consent, New conversation, Improve a taf, Report this answer (`coach/CoachView.swift`, `Core/coach/Thread.swift`, `Stream.swift`, `Rich.swift`, `Chats.swift`) | Approving a connection or a Card; Previous conversations and archiving; attachments; dictation; `SetupShapePanel`, `CoachToolsStep`, `QuestionsCard`, `DriveCard` |
| ShareViews.swift | 405 | Sharing a taf (`ShareLine`, `ShareTafSheet`), and the Overview (`OverviewView`) | `ShareLine` under a taf's head (`taf/TafShareLine.swift`, `Core/account/Shares.swift`); the Overview (`overview/OverviewView.swift`) | `ShareTafSheet`: sharing is signed with Face ID on the iPad, so it waits for this Mac to approve |
| SignInView.swift | 333 | `SignInView`, and Account (`SettingsView`, `PlanRow`, `AccountView`, `AccountLines`) | Sign in in the browser (`pairing/SignInView.swift`, `SignInModel.swift`); Account's groups and rows, `PlanRow`, `AccountLines.people`, Sign out confirmed first (`account/AccountView.swift`) | Coach's suggestions; AI use; Time zone; Delete account |
| TafChatView.swift | 826 | A taf's chat | The taf's conversation drawn as Coach's, its box, its Cards beside it (`taf/TafView.swift`, `coach/CoachView.swift`) | What Coach's conversation also misses (attachments, dictation, questions); `SteadyMarkdown` |
| TafDetailView.swift | 1474 | A taf's page: head, tabs, Card, Activity, Setup, panels | The head and its state chip, the version line and Versions, the share line, the four tabs, the Card wallet (`CardStack`), the halt row (`taf/TafView.swift`, `TafTabsView.swift`, `Core/taf/TafCard.swift`, `TafTabs.swift`, `TafVersions.swift`) | Starts when and Results go to; the Doors tab; `RunsPanel`; the rest of `WorkPanel`; Pause; Forget a note; the workflow steps' rows; Connect again |
| TafPresentationViews.swift | 492 | A taf's Activity list and Setup panels | `CardUnitExceptionPanel`; `ConnectedToolsRing` as a list, with `ConnectedAppSheet`; `TafActivityList`'s filters, groups and pages; `MemorySummaryPanel`'s notes (`taf/TafTabsView.swift`, `Core/taf/TafTabs.swift`) | `NextStepRow`'s buttons; `TafKnocksPanel`; `RetainedRuns`; opening an app's week in Activity |
| UsageView.swift | 348 | Plan & usage: the balance, buying, who bills, members' requests | The balance and its meter, the credits, each half read on its own (`usage/UsageView.swift`, `Core/usage/Usage.swift`) | Raise the limit (an approval); Ask an admin and Withdraw; Manage. Buying is not for macOS 12 (see `PlanViews.swift`) |
| WorkLog.swift | 181 | What a taf does while it answers | `WorkLog.rows`, the live line with its steps, `StepList`, "Worked for" opening the steps (`Core/coach/WorkRows.swift`, `coach/CoachView.swift`) | `SteadyMarkdown` |

## Not started

| iPad file | Lines | What | Models |
| :- | -: | :- | :- |
| AllowSheetView.swift | 96 | "Allow this from now on" | HoldAllow |
| AppEventApprovalSheet.swift | 54 | An app event's filters before signing a subscription | |
| AttachViews.swift | 267 | Attaching photos and files in a chat | |
| CoachToolsStep.swift | 255 | Coach's tools still to give | |
| DeleteAccountView.swift | 60 | Deleting the account | |
| DiscardSettingUp.swift | 35 | Discard a taf being set up | |
| DoorsView.swift | 923 | A taf's Doors tab | |
| DriveViews.swift | 73 | Coach asks to drive the app | |
| MicButton.swift | 122 | The mic in a chat's message bar | |
| QuestionsCard.swift | 121 | Several questions at once | QuestionAnswers |
| RecipeGallery.swift | 135 | The jobs' gallery | |
| SetupShapePanel.swift | 130 | What Coach has made so far | SetupShape |
| TafDialPanel.swift | 228 | The dial's requests and confirmation | |
| TafKnobView.swift | 377 | The taf's remote | KnobNavigation |
| TafSetupViews.swift | 512 | Starts when, Results go to, the knob's pending changes | |
| TrialViews.swift | 214 | Trials of a new version | |

## Not for macOS 12

| iPad file | Lines | Why |
| :- | -: | :- |
| PairComputerView.swift | 222 | The phone's side of pairing: its camera reads a computer's code. This Mac is the computer being added. |
| PlanViews.swift | 268 | Buying credits and a plan through the App Store. This app isn't sold through a store, and the Mac buys nothing. |
| TafKnobRemote.swift | 64 | Keeps the remote above the phone's tab bar. The Mac has no tab bar. |
| TafsBar.swift | 121 | The phone's bar along the foot. The Mac has the sidebar (`HomeSplitView`). |

## In review

Pull requests open against `main`, not counted above. Each updates its lines here as it
merges.

| PR | iPad files | Mac files it changes |
| :- | :- | :- |
| #80 A taf's runs | TafDetailView (`RunsPanel`, Run now), TafPresentationViews (`RetainedRuns`) | `taf/TafRunsView.swift`, `RunNowModel.swift`, `TafTabsView.swift`, `Core/taf/TafRuns.swift` |
| #81 The jobs' gallery | RecipeGallery, HomeSplitView (+ New, Explore) | `overview/RecipeGalleryView.swift`, `HomeRecipesView.swift`, `OverviewView.swift`, `shell/ShellView.swift`, `Core/overview/Gallery.swift` |
| #82 The knob's dial | TafSetupViews (Starts when, Results go to) | `taf/KnobSetupView.swift`, `base/AccountTime.swift`, `TafView.swift`, `Core/taf/TafKnob.swift` |
| #83 Doors | DoorsView, TafPresentationViews (`TafKnocksPanel`), NeedsYouView (knocks) | `taf/TafDoorsViews.swift`, `TafDoorsModel.swift`, `approvals/NeedsYou.swift`, `Core/taf/TafDoors.swift` |
| #89 Coach's title row and Previous conversations | CoachMode (Back), SetupChatView (`SetupChatsList`, `startNewTaf`) | `coach/CoachChatsSheet.swift`, `CoachView.swift`, `shell/ShellView.swift` |
| #90 Start-up | HomeView (the list remembered for the first frame) | `overview/OverviewView.swift`, `Core/overview/RememberedHome.swift`, `entry/TafsApp.swift` |
| #91 Setup's proof | TafDetailView's Setup read with this device's planque proof | `taf/TafTabsView.swift`, `Core/taf/PlanqueClient.swift`, `Core/base/CloudClient.swift` |
| #94 Devices test | None: a test only | `Tests/account/mac/DevicesTests.swift` |

## Counts

Ported 4, partial 26, not started 16, not for macOS 12 4: the 50 view files at the pin
(`da55768`).
