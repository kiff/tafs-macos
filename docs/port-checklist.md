# The port checklist

Each iPad view file (kiff/tafs `ios/Tafs/Views`, at the pin in `shared.pin`) against its
state on this Mac. A file is **ported** when every branch it draws is on this Mac, **partial**
when part of it is (what's missing is named), **not started**, or **not for macOS 12** (and
why). It's judged from `main`'s code and docs, not from pull requests still in review. The PR
that ports a file updates its line here.

Paths under "Mac" are in `Sources/App` unless they start with `Core/` (`Sources/Core`). The
checklist moves with `shared.pin`. Screens outside `Views/` (`Drive/DriveOverlay.swift`, the
`Design/` building blocks, `App/TafsApp.swift`) are out of its scope.

## Ported

| iPad file | Lines | What | Models | Mac |
| :- | -: | :- | :- | :- |
| ExportChatsView.swift | 82 | Account › Export my chats | AppModel.exportChats | `account/ExportChatsView.swift`, `Core/account/ChatsExport.swift` |
| MicButton.swift | 122 | The mic in a chat's message bar, its language switch and the listening bar | Dictation (`Services/Dictation.swift`) | `coach/MicButton.swift`, `coach/Dictation.swift`, `Core/coach/Dictating.swift`, in Coach's and a taf's message bar |
| PairSignInView.swift | 104 | Signing in from another phone: this device shows the pairing QR and its check code, the phone approves | KIFF/Pairing | "Add this Mac with a phone": `pairing/SignInView.swift`, `SignInModel.swift`, `QRCode.swift`, `Core/pairing/Client.swift`, `Messages.swift` |
| ReportAnswerSheet.swift | 124 | Report an answer Coach or a taf wrote | AnswerReport | `coach/ReportAnswerSheet.swift`, `Core/coach/Report.swift` |
| YourStepCard.swift | 46 | A step a taf handed its owner, with Done and Skip | YourStep | `approvals/NeedsYou.swift`, `Core/approvals/YourStep.swift` (signed with the device key after Touch ID or the Mac's password) |

## Partial

| iPad file | Lines | What | Mac has | Missing |
| :- | -: | :- | :- | :- |
| AIConsentView.swift | 74 | The AI-data consent, and Account's AI use row | Coach's consent sheet: the words, Allow, Not now (`coach/CoachView.swift`, `Core/contracts/AIConsent.swift`) | `AIConsentRow` (Account › AI use) |
| AccountPreferencesView.swift | 37 | Account's theme and time zone pickers | `ThemePicker`: Light, Dark, System, kept across launches (`account/AccountView.swift`) | `TimeZonePicker` |
| ApprovalSetupView.swift | 102 | This device's approval readiness: `ReadinessReader`, `ApprovalGate`, `ApprovalNotice`, `ApprovalNotReady` | `ApprovalNotReady`'s line where an approval can't be made here (`approvals/NeedsYou.swift`, `taf/HaltView.swift`) | `ReadinessReader`, `ApprovalGate`, `ApprovalNotice`: no Mac approves yet |
| AttachViews.swift | 267 | Attaching photos and files in a chat | `AttachButton` (Choose photos, Choose file, as many as the message has room for), `FileTray`, `FileChip`, `FileIcon`, `MessageFiles`; each file declared to tafs cloud and its bytes put to storage, sent with the message by id (`coach/ChatFilesViews.swift`, `FilePrepMac.swift`, `CoachView.swift`, `Core/coach/ChatFiles.swift`) | Take photo (this Mac's camera); Quick Look in place (a file opens in the app this Mac opens its kind with) |
| CalendarView.swift | 434 | Calendar: the month card, Day, Week, Month | All three views, the month card, the agenda, today in the account's zone (`calendar/CalendarView.swift`, `Core/calendar/Agenda.swift`) | Opening a taf from an event |
| CoachMode.swift | 131 | Coach mode over the app: `CoachView`, `CoachPanel`, `PhoneCoachPanel` | Coach as a screen of the window, with its title and New conversation (`coach/CoachView.swift`) | Coach mode over the app and over a taf's page: the panel, the dimmed ground, Back, a tap outside. `PhoneCoachPanel` is the phone's |
| ConnectAppsView.swift | 1141 | Connect apps, a connected app's detail, connecting's approval | The search, Yours and Discover, the table (`ConnectColumns`), each row's end in `connectFor`'s words (Ask Coach), the chevron, logos read through the app's transport (`AppLogos`), More apps, Not listed? Ask Coach (`connections/ConnectAppsView.swift`, `connections/AppLogoView.swift`, `Core/connections/Apps.swift`, `Core/connections/AppLogos.swift`); `AppConnectionsView`, read only, its actions drawn and a click saying to approve elsewhere (`connections/AppConnectionsView.swift`, `Core/connections/AppConnections.swift`); `ConnectApprovalSheet`'s receipt with board 5, shown over Coach once a connection it showed waiting is made (`connections/ConnectReceiptSheet.swift`, `Core/connections/ConnectReceipt.swift`, `coach/CoachView.swift`) | Connecting and Sign in again from here; Connect off with "Make one first" for no taf; the rest of `ConnectApprovalSheet` (the approval, the key's sheet, the receipt's logo, host, last 4 characters and Disconnect); `ConnectionDetailView`; a connection's last failed call and "Also on …'s Card"; Disconnect and Clear (each with its approval) |
| CreditsViews.swift | 181 | The credits the account's tafs used, and one taf's runs | `CreditsPanel`: both periods, each taf's line, Coach, not counted, the note (`usage/UsageView.swift`, `Core/usage/Usage.swift`); `TafCreditsView` and `CreditsRunRow` as a taf's Usage, from its Card tab (`taf/TafCreditsView.swift`, `Core/taf/TafCredits.swift`) | Opening a taf's run (`KnobRequestDetail`); a taf's line in `CreditsPanel` opening its runs; the period before on a taf's runs |
| DevicesView.swift | 69 | Account › Devices | The list, every row's sheet, This device, this Mac's own Sign out (`account/Devices.swift`, `Core/account/Account.swift`) | Signing another device out, which becomes the iPad's signed approval (`prepareRemoveDevice`, `signApproval`) first |
| HaltScreen.swift | 176 | A halt of one taf or every taf | Halt now and Halt all now, the parts that hold it, following while halting, board 4 once every taf is halted (`taf/HaltView.swift`, `Core/taf/Halt.swift`, `Core/shell/ArtBoard.swift`) | Resume, which gives authority back and is signed |
| HomeRecipes.swift | 242 | Home with no taf: the recipes | `HomeRecipes`, `OwnWordsRow`, `RecipeRow`, `AppMarks` and `AppMark` with each app's logo (`AppLogo`), `RecipeSheet` (`overview/HomeRecipesView.swift`, `connections/AppLogoView.swift`, `Core/overview/Recipes.swift`) | Handing a recipe to a new Coach conversation; Own words opening a new conversation (`startNewTaf`) |
| HomeSplitView.swift | 584 | The sidebar for the whole app and what it opens | The brand, the screens with Needs you's count (the iPad's `needsYouCount`, `Core/approvals/CoachWaiting.swift`), Halt all under Connect apps (`haltAllRow`, `showsAccountHalt`: `shell/HaltAllItem.swift`, `Core/shell/AccountHalt.swift`), NEEDS YOU's held calls, each named as `proposed.summary`, YOUR TAFS in the iPad's order (`listedTafs`, `Core/overview/ListOrder.swift`) with each taf's line, Start a new taf, Coach, Account (`shell/ShellView.swift`, `shell/SignedInView.swift`, `Core/shell/Screen.swift`, `HeldRow.swift`) | Shared with you; Other agents; tafs being set up and Discard; the recipes strip and Explore; + New's gallery; the Unreachable and Plan lines at the foot |
| NeedsYouView.swift | 603 | Needs you: held calls, "Did this happen?", steps, Coach's waits, knocks, alerts | Held calls (`HeldCallCard`'s face, named as `proposed.summary`, and countdown) with Refuse; "Did this happen?" without its Yes or No; Your step; Card unit requests; `CoachWaitingCard` with Open Coach and Set aside, and `SetAllAsideButton` (`approvals/CoachWaitingCard.swift`, `Core/approvals/CoachWaiting.swift`); the empty state with board 6 (`approvals/NeedsYou.swift`, `Core/approvals/HeldCalls.swift`, `CallNames.swift`, `Unproven.swift`) | Approve once and Extra room; next steps; Allow from now on; Refuse's Touch ID or password confirmation; `CoachWaitingCard`'s swipe (its button is on the Mac); `AlertsCard`; knocks |
| NotificationSettingsView.swift | 138 | Account › Alerts | What an alert looks like (`LockScreenAlert`), Alerts on this Mac, Sound, kept per account (`account/AlertsView.swift`, `approvals/Notifier.swift`, `Core/approvals/AlertPrefs.swift`) | `AlertingTafsView` (which tafs alert); alerts with tafs closed, which need a signed build |
| OnboardingView.swift | 63 | The welcome: what tafs is, Sign in with KIFF, Try it with sample data | The welcome and Sign in with KIFF, with board 1's drawing (`pairing/SignInView.swift`, `base/Illustrations.swift`) | Try it with sample data |
| PeopleViews.swift | 291 | People and groups | The groups and the people, read every 20 seconds, in the iPad's order (`account/PeopleView.swift`, `Core/account/People.swift`) | Making, renaming or deleting a group and changing its people (each signed) |
| PlanViews.swift | 268 | Asking an admin and declining a member's request; buying credits and Solo | `AskAdminView` (raise or pack, with a reason) and `DeclineRequestView` (with a note, confirmed and signed), as sheets (`usage/PlanRequestsView.swift`, `Core/usage/KIFFUsage.swift`) | Nothing to port: `BuyCreditsView` and `SoloView` are the App Store's, not for macOS 12 |
| QuestionsCard.swift | 121 | Several questions at once | Every question with Coach's options and Something else…, the count answered, Send answers once each has one, Chat about this, and the answered line (`coach/QuestionsCard.swift`, `Core/coach/Questions.swift`, `CoachModel.answer(_:questions:)`) | An answer sent the old way, as a message, read back in words (`QuestionAnswers.words`); a refusal for want of the AI-data consent keeping the card quietly (it says tafs cloud's why here); following the answered run's stream (the Mac reads the thread) |
| RecordSearchViews.swift | 192 | The Record's search, Export receipts | The search as the person pauses, its pages on More, `RecordHitRow`, `RecordCaseSheet` (`record/RecordView.swift`, `Core/record/Record.swift`); `ExportReceiptsRow`, saved with a save panel where the iPad shares (`record/ExportReceiptsRow.swift`, `Core/record/ReceiptsExport.swift`) | A case's steps as `SourceActivityRow`, with each step's next step |
| RecordView.swift | 714 | The Record, its rows, filters and receipts | The list, the taf chips, the filters, days (`days`, `dayTitle`, in the account's zone), a day's reads folded into one line with Show and Hide, and rows with the iPad's second line (`decidedLine`, `resultLine`), paging (`record/RecordView.swift`, `Core/record/Record.swift`, `Core/record/RecordLines.swift`, `base/AccountTime.swift`); `ReceiptView`: a line's sheet with KIFF's receipt checked on this Mac (`record/ReceiptSheet.swift`, `Core/record/ReceiptCheck.swift`, `Secp256k1.swift`, `Keccak256.swift`) | A day's spend in its title (summed in `Record.spent`; `record.day_spent` isn't at the pin); a row's `onText`; "no longer waiting" for a held call; the receipt's payment check (`on_hash`); a taf's detail |
| SetupChatView.swift | 1957 | Coach's conversation | The thread, the answer as it's written, cards answered, questions answered (`QuestionsCard`), Decline, an approval's and a sign-in's wider line (`WiderLine`, `coach/WiderLine.swift`), the AI-data consent, New conversation, Improve a taf, Report this answer, Previous conversations with Archive and Archived (`coach/CoachChatsSheet.swift`), Start as `introBefore`'s on the security key's route (switched off; on a Mac that can't approve, why and following the phone's start), boards 9 and 7 on its start and its empty chat (`coach/CoachView.swift`, `Core/coach/CoachStart.swift`, `Core/coach/Thread.swift`, `Stream.swift`, `Rich.swift`, `Chats.swift`) | Approving a connection or a Card; attachments; `SetupShapePanel`, `CoachToolsStep`, `DriveCard` |
| ShareViews.swift | 405 | Sharing a taf (`ShareLine`, `ShareTafSheet`), and the Overview (`OverviewView`) | `ShareLine` under a taf's head, with Share beside it, whose click says to approve on another device (`taf/TafShareLine.swift`, `Core/account/Shares.swift`); the Overview (`overview/OverviewView.swift`), with board 10 under its title, its label chips and each taf's labels (`overview/LabelChipsView.swift`, `Core/overview/HomeLabels.swift`), the rows in `listedTafs`' order (`Core/overview/ListOrder.swift`), `usedBy` under each name (`Core/account/Shares.swift`), and Last result by the list's `last_run` until read (`Core/overview/LastResult.swift`) | `ShareTafSheet`: sharing is signed with Face ID on the iPad, so it waits for this Mac to approve; the Overview reading its list again by itself |
| SignInView.swift | 333 | `SignInView`, and Account (`SettingsView`, `PlanRow`, `AccountView`, `AccountLines`) | Sign in in the browser (`pairing/SignInView.swift`, `SignInModel.swift`); Account's groups and rows, `PlanRow`, `AccountLines.people`, Sign out confirmed first (`account/AccountView.swift`) | Coach's suggestions; AI use; Time zone; Delete account |
| TafChatView.swift | 826 | A taf's chat | The taf's conversation drawn as Coach's, its box, its Cards beside it, its `ask_coach` cards with Ask Coach (`taf/TafView.swift`, `coach/CoachView.swift`, `Core/coach/Thread.swift`) | What Coach's conversation also misses (attachments, questions); `SteadyMarkdown` |
| TafDetailView.swift | 1474 | A taf's page: head, tabs, Card, Activity, Setup, panels | The head and its state chip, the version line and Versions, the share line with Share, the four tabs, the Cards beside the Chat and the Activity, the Card wallet (`CardStack`) with its issuer, the Card tab's time zone words, How this is counted (`CountedView`), Halt, its versions, Usage and Revoke (whose click says to approve elsewhere), the Setup in the iPad's order with the job and Improve in Coach, `MemoryPanel` with Forget, `RunsPanel` (`taf/TafView.swift`, `TafCardTab.swift`, `TafTabsView.swift`, `TafMemoryView.swift`, `Core/taf/TafCard.swift`, `TafTabs.swift`, `TafVersions.swift`, `TafMemory.swift`) | The rest of `WorkPanel`; the Card tab's `each_item`, `pending` and `unit_words` lines; Remove for good and Revoke themselves (each signed); the workflow steps' rows; Connect again; folding the header while the chat scrolls |
| TafSetupViews.swift | 512 | Starts when, Results go to, the knob's pending changes | `StartsWhenView` (its schedule with −/+ as wide as the iPad's, app events, its doors, follow-ups, Change when it starts with Coach, Pause), `ResultsGoToView` (tafs' own places, places in apps, Add a place from a connected app, a locked-on switch green), `KnobPendingPanel`, `SizeStepper`, `DoorsList` (`taf/KnobSetupView.swift`, `TafDoorsViews.swift`, `Core/taf/TafKnob.swift`) | Not sent with Send again (the taf's work); Make it live and approving an app event, each signed |
| TafPresentationViews.swift | 492 | A taf's Activity list and Setup panels | `CardUnitExceptionPanel`; `ConnectedToolsRing` as the iPad's ring, with its workflow and `ConnectedAppSheet`; `TafActivityList`'s filters, groups and pages, each call a plain row as `SourceActivityRow`; `MemorySummaryPanel` with See all; `RetainedRuns`; `TafKnocksPanel` (`taf/TafToolsRing.swift`, `taf/TafTabsView.swift`, `taf/TafRunsView.swift`, `taf/TafDoorsViews.swift`, `Core/taf/TafTabs.swift`) | `NextStepRow`'s buttons; a call's receipt from its row; the workflow's steps |
| UsageView.swift | 348 | Plan & usage: the balance, buying, who bills, members' requests | The balance and its meter, the credits, each half read on its own; KIFF's usage read; `askPanel` (a member's request waiting with Withdraw, the last answer, Ask an admin) and `requestsPanel` (members' requests with Decline) (`usage/UsageView.swift`, `PlanRequestsView.swift`, `Core/usage/Usage.swift`, `KIFFUsage.swift`) | Raise the limit (an approval), also as a raise request's answer; who bills the plan (`billingPanel`) and Manage. Buying credits and Solo are not for macOS 12 (`PlanViews.swift`'s store views) |
| WorkLog.swift | 181 | What a taf does while it answers | `WorkLog.rows`, the live line with its steps, `StepList`, "Worked for" opening the steps (`Core/coach/WorkRows.swift`, `coach/CoachView.swift`) | `SteadyMarkdown` |

## Not started

| iPad file | Lines | What | Models |
| :- | -: | :- | :- |
| AllowSheetView.swift | 96 | "Allow this from now on" | HoldAllow |
| AppEventApprovalSheet.swift | 54 | An app event's filters before signing a subscription | |
| CoachToolsStep.swift | 255 | Coach's tools still to give | |
| DeleteAccountView.swift | 60 | Deleting the account | |
| DiscardSettingUp.swift | 35 | Discard a taf being set up | |
| DoorsView.swift | 923 | A taf's Doors tab | |
| DriveViews.swift | 73 | Coach asks to drive the app | |
| RecipeGallery.swift | 135 | The jobs' gallery | |
| SetupShapePanel.swift | 130 | What Coach has made so far | SetupShape |
| TafDialPanel.swift | 228 | The dial's requests and confirmation | |
| TafKnobView.swift | 377 | The taf's remote | KnobNavigation |
| TrialViews.swift | 214 | Trials of a new version | |

## Not for macOS 12

| iPad file | Lines | Why |
| :- | -: | :- |
| HomeView.swift | 403 | The phone's compact home (`TafsTab` draws it only below regular width, HomeSplitView.swift:10-14). This Mac always has the sidebar: its Overview is `ShareViews`' `OverviewView`, and no taf's recipes are `HomeRecipes`. Its board 2, no tafs yet, is the Overview's with no taf and no job listed. |
| PairComputerView.swift | 222 | The phone's side of pairing: its camera reads a computer's code. This Mac is the computer being added. |
| TafKnobRemote.swift | 64 | Keeps the remote above the phone's tab bar. The Mac has no tab bar. |
| TafsBar.swift | 121 | The phone's bar along the foot. The Mac has the sidebar (`HomeSplitView`). |

## In review

Pull requests open against `main`, not counted above. Each updates its lines here as it
merges.

| PR | iPad files | Mac files it changes |
| :- | :- | :- |
| #80 A taf's runs | TafDetailView (`RunsPanel`, Run now), TafPresentationViews (`RetainedRuns`) | `taf/TafRunsView.swift`, `RunNowModel.swift`, `TafTabsView.swift`, `Core/taf/TafRuns.swift` |
| #81 The jobs' gallery | RecipeGallery, HomeSplitView (+ New, Explore) | `overview/RecipeGalleryView.swift`, `HomeRecipesView.swift`, `OverviewView.swift`, `shell/ShellView.swift`, `Core/overview/Gallery.swift` |
| #82 Setup: Starts when and Results go to | TafSetupViews (Starts when, Results go to) | `taf/KnobSetupView.swift`, `base/AccountTime.swift`, `TafView.swift`, `Core/taf/TafKnob.swift` |
| #83 Doors | DoorsView, TafPresentationViews (`TafKnocksPanel`), NeedsYouView (knocks) | `taf/TafDoorsViews.swift`, `TafDoorsModel.swift`, `approvals/NeedsYou.swift`, `Core/taf/TafDoors.swift` |
| #89 Coach's title row and Previous conversations | CoachMode (Back), SetupChatView (`SetupChatsList`, `startNewTaf`) | `coach/CoachChatsSheet.swift`, `CoachView.swift`, `shell/ShellView.swift` |
| #90 Start-up | HomeView (the list remembered for the first frame) | `overview/OverviewView.swift`, `Core/overview/RememberedHome.swift`, `entry/TafsApp.swift` |
| #91 Setup's proof | TafDetailView's Setup read with this device's planque proof | `taf/TafTabsView.swift`, `Core/taf/PlanqueClient.swift`, `Core/base/CloudClient.swift` |
| #94 Devices test | None: a test only | `Tests/account/mac/DevicesTests.swift` |
| #95 Refuse's confirmation | NeedsYouView (Refuse's Touch ID or password) | `approvals/NeedsYou.swift`, `Core/approvals/HeldCalls.swift` |

## Counts

Ported 5, partial 29, not started 12, not for macOS 12 4: the 50 view files at the pin
(`da55768`).
