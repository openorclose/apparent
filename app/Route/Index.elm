module Route.Index exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.Time
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Head
import Html
import Html.Attributes as Attr
import Html.Events as Events
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Marketplace exposing (Listing)
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute)
import Shared
import String
import Task
import Time
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    { query : String
    , category : Maybe Marketplace.Category
    , neighborhood : Maybe Marketplace.Neighborhood
    , sortOrder : Marketplace.SortOrder
    , page : Int
    , now : Int
    , sampleListings : List Marketplace.PublishedListing
    , serverListings : List Marketplace.PublishedListing
    , dialog : Dialog
    , draft : ListingDraft
    , submission : Submission
    , notice : Maybe String
    }


type Dialog
    = NoDialog
    | CreateListingDialog
    | ListingDetailsDialog String


type Submission
    = ReadyToSubmit
    | Submitting


type alias ListingDraft =
    { title : String
    , category : Marketplace.Category
    , neighborhood : Marketplace.Neighborhood
    , price : String
    , contact : String
    , description : String
    }


type Msg
    = SearchChanged String
    | CategorySelected (Maybe Marketplace.Category)
    | NeighborhoodSelected String
    | SortByPrice
    | PageSelected Int
    | ShowCreateForm
    | HideCreateForm
    | TitleChanged String
    | CategoryDraftChanged String
    | NeighborhoodDraftChanged String
    | PriceChanged String
    | ContactChanged String
    | DescriptionChanged String
    | CreateListing
    | ListingCreated (Result Http.Error Marketplace.PublishedListing)
    | ListingsLoaded (Result Http.Error (List Marketplace.PublishedListing))
    | ClockUpdated Time.Posix
    | OpenListing String
    | CloseListing
    | DismissNotice


type alias RouteParams =
    {}


type alias Data =
    { generatedAt : Int
    , listings : List Marketplace.PublishedListing
    }


type alias ActionData =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


data : BackendTask FatalError Data
data =
    BackendTask.map2
        (\generatedAt listings ->
            { generatedAt = Time.posixToMillis generatedAt
            , listings = List.map (Marketplace.publishListing (Time.posixToMillis generatedAt)) listings
            }
        )
        BackendTask.Time.now
        (BackendTask.succeed Marketplace.sampleListings)


init : App Data ActionData RouteParams -> Shared.Model -> ( Model, Effect Msg )
init app sharedModel =
    ( { query = ""
      , category = Nothing
      , neighborhood = Nothing
      , sortOrder = Marketplace.Recommended
      , page = 1
      , now = app.data.generatedAt
      , sampleListings = app.data.listings
      , serverListings = []
      , dialog = NoDialog
      , draft =
            { title = ""
            , category = Marketplace.Tools
            , neighborhood = Marketplace.Maplewood
            , price = "0"
            , contact = ""
            , description = ""
            }
      , submission = ReadyToSubmit
      , notice = Nothing
      }
    , Effect.batch
        [ Effect.fromCmd (Task.perform ClockUpdated Time.now)
        , Effect.fromCmd loadListings
        ]
    )


update :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update app shared msg model =
    case msg of
        SearchChanged query ->
            ( { model | query = query, page = 1 }, Effect.none )

        CategorySelected category ->
            ( { model | category = category, page = 1 }, Effect.none )

        NeighborhoodSelected neighborhood ->
            case neighborhood of
                "" ->
                    ( { model | neighborhood = Nothing, page = 1 }, Effect.none )

                name ->
                    case Marketplace.neighborhoodFromName name of
                        Just value ->
                            ( { model | neighborhood = Just value, page = 1 }, Effect.none )

                        Nothing ->
                            ( model, Effect.none )

        SortByPrice ->
            ( { model
                | sortOrder =
                    case model.sortOrder of
                        Marketplace.Recommended ->
                            Marketplace.PriceAscending

                        Marketplace.PriceAscending ->
                            Marketplace.Recommended
                , page = 1
              }
            , Effect.none
            )

        PageSelected page ->
            ( { model | page = max 1 page }, Effect.none )

        ShowCreateForm ->
            ( { model | dialog = CreateListingDialog, notice = Nothing }, Effect.none )

        HideCreateForm ->
            ( { model | dialog = NoDialog }, Effect.none )

        TitleChanged title ->
            ( { model | draft = updateDraft model.draft (\draft -> { draft | title = title }) }, Effect.none )

        CategoryDraftChanged category ->
            case Marketplace.categoryFromName category of
                Just value ->
                    ( { model | draft = updateDraft model.draft (\draft -> { draft | category = value }) }, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        NeighborhoodDraftChanged neighborhood ->
            case Marketplace.neighborhoodFromName neighborhood of
                Just value ->
                    ( { model | draft = updateDraft model.draft (\draft -> { draft | neighborhood = value }) }, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        PriceChanged price ->
            ( { model | draft = updateDraft model.draft (\draft -> { draft | price = price }) }, Effect.none )

        ContactChanged contact ->
            ( { model | draft = updateDraft model.draft (\draft -> { draft | contact = contact }) }, Effect.none )

        DescriptionChanged description ->
            ( { model | draft = updateDraft model.draft (\draft -> { draft | description = description }) }, Effect.none )

        CreateListing ->
            if model.submission == Submitting then
                ( model, Effect.none )

            else
                submitListing model

        ListingCreated result ->
            case result of
                Ok published ->
                    ( { model
                        | serverListings = published :: model.serverListings
                        , dialog = NoDialog
                        , draft = emptyDraft
                        , submission = ReadyToSubmit
                        , notice = Just "Your item is live for the next 7 days. Share your contact details and neighbors can reach you directly."
                      }
                    , Effect.none
                    )

                Err error ->
                    ( { model
                        | submission = ReadyToSubmit
                        , notice = Just ("Could not save your listing. " ++ httpErrorMessage error)
                      }
                    , Effect.none
                    )

        ListingsLoaded result ->
            case result of
                Ok listings ->
                    ( { model | serverListings = mergeListings listings model.serverListings }, Effect.none )

                Err error ->
                    ( { model
                        | notice = Just ("Could not load shared listings from the server. " ++ httpErrorMessage error)
                      }
                    , Effect.none
                    )

        ClockUpdated currentTime ->
            let
                now =
                    Time.posixToMillis currentTime

                samples =
                    Marketplace.expireListings now model.sampleListings

                serverListings =
                    Marketplace.expireListings now model.serverListings

                listingStillExists listingId =
                    List.any
                        (\published -> Marketplace.listingId (Marketplace.publishedListing published) == listingId)
                        (samples ++ serverListings)

                dialog =
                    case model.dialog of
                        ListingDetailsDialog listingId ->
                            if listingStillExists listingId then
                                model.dialog

                            else
                                NoDialog

                        _ ->
                            model.dialog
            in
            ( { model
                | now = now
                , sampleListings = samples
                , serverListings = serverListings
                , dialog = dialog
              }
            , Effect.fromCmd loadListings
            )

        OpenListing listingId ->
            ( { model | dialog = ListingDetailsDialog listingId, notice = Nothing }, Effect.none )

        CloseListing ->
            ( { model | dialog = NoDialog }, Effect.none )

        DismissNotice ->
            ( { model | notice = Nothing }, Effect.none )


updateDraft : ListingDraft -> (ListingDraft -> ListingDraft) -> ListingDraft
updateDraft draft transform =
    transform draft


submitListing : Model -> ( Model, Effect Msg )
submitListing model =
    case ( Marketplace.priceFromInput model.draft.price, Marketplace.categoryFromName (Marketplace.categoryName model.draft.category) ) of
        ( Err message, _ ) ->
            ( { model | notice = Just message }, Effect.none )

        ( _, Nothing ) ->
            ( { model | notice = Just "Choose a valid listing category." }, Effect.none )

        ( Ok price, Just category ) ->
            case
                Marketplace.createListing
                    { id = "validation-only"
                    , title = model.draft.title
                    , category = category
                    , neighborhood = model.draft.neighborhood
                    , owner = "A neighbor"
                    , price = price
                    , contact = model.draft.contact
                    , emoji = "📦"
                    , artClass = "art-mint"
                    , description = model.draft.description
                    }
            of
                Err message ->
                    ( { model | notice = Just message }, Effect.none )

                Ok _ ->
                    ( { model | submission = Submitting, notice = Nothing }
                    , Effect.fromCmd
                        (Http.post
                            { url = "/api/listings"
                            , body = Http.jsonBody (listingRequestEncoder model.draft)
                            , expect = Http.expectJson ListingCreated Marketplace.publishedListingDecoder
                            }
                        )
                    )


listingRequestEncoder : ListingDraft -> Encode.Value
listingRequestEncoder draft =
    Encode.object
        [ ( "title", Encode.string draft.title )
        , ( "category", Encode.string (Marketplace.categoryName draft.category) )
        , ( "neighborhood", Encode.string (Marketplace.neighborhoodName draft.neighborhood) )
        , ( "price", Encode.string draft.price )
        , ( "contact", Encode.string draft.contact )
        , ( "description", Encode.string draft.description )
        ]


emptyDraft : ListingDraft
emptyDraft =
    { title = ""
    , category = Marketplace.Tools
    , neighborhood = Marketplace.Maplewood
    , price = "0"
    , contact = ""
    , description = ""
    }


loadListings : Cmd Msg
loadListings =
    Http.get
        { url = "/api/listings"
        , expect = Http.expectJson ListingsLoaded (Decode.list Marketplace.publishedListingDecoder)
        }


mergeListings : List Marketplace.PublishedListing -> List Marketplace.PublishedListing -> List Marketplace.PublishedListing
mergeListings latest existing =
    let
        latestIds =
            List.map (Marketplace.listingId << Marketplace.publishedListing) latest

        notAlreadyLoaded listing =
            not (List.member (Marketplace.listingId (Marketplace.publishedListing listing)) latestIds)
    in
    latest ++ List.filter notAlreadyLoaded existing


httpErrorMessage : Http.Error -> String
httpErrorMessage error =
    case error of
        Http.BadUrl _ ->
            "The server URL was invalid."

        Http.Timeout ->
            "The request timed out. Please try again."

        Http.NetworkError ->
            "The server could not be reached. Please try again."

        Http.BadStatus status ->
            "The server returned status " ++ String.fromInt status ++ "."

        Http.BadBody _ ->
            "The server returned an unreadable response."


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions routeParams path sharedModel model =
    Time.every 30000 ClockUpdated


head : App Data ActionData RouteParams -> List Head.Tag
head _ =
    []


view : App Data ActionData RouteParams -> Shared.Model -> Model -> View (PagesMsg Msg)
view app sharedModel model =
    let
        allListings =
            List.map Marketplace.publishedListing (Marketplace.expireListings model.now (model.sampleListings ++ model.serverListings))

        activePublishedListings =
            Marketplace.expireListings model.now (model.sampleListings ++ model.serverListings)

        filteredListings =
            Marketplace.filterListings
                { query = model.query
                , category = model.category
                , neighborhood = model.neighborhood
                }
                allListings
                |> sortListings model.sortOrder

        pageSize =
            6

        pageTotal =
            Marketplace.pageCount pageSize (List.length filteredListings)

        visibleListings =
            Marketplace.paginate model.page pageSize filteredListings

        activeListing =
            case model.dialog of
                ListingDetailsDialog listingId ->
                    List.filter
                        (\published -> Marketplace.listingId (Marketplace.publishedListing published) == listingId)
                        activePublishedListings
                        |> List.head

                _ ->
                    Nothing
    in
    { title = "AppaRent — Good things, shared nearby"
    , body =
        [ Html.div [ Attr.class "page-wrap" ]
            [ hero model
            , browseSection model visibleListings (List.length filteredListings) pageTotal
            , Html.section [ Attr.class "community-note" ]
                [ Html.span [ Attr.class "community-note-icon", Attr.attribute "aria-hidden" "true" ] [ Html.text "✳" ]
                , Html.div []
                    [ Html.h2 [] [ Html.text "A little sharing goes a long way." ]
                    , Html.p [] [ Html.text "Borrow what you need. Lend what you love. Get to know the people just around the corner." ]
                    ]
                , Html.button
                    [ Attr.class "button button-light"
                    , Events.onClick (PagesMsg.fromMsg ShowCreateForm)
                    ]
                    [ Html.text "Share an item" ]
                ]
            ]
        , case model.dialog of
            CreateListingDialog ->
                createDialog model

            ListingDetailsDialog _ ->
                activeListing
                    |> Maybe.map (listingDialog model.now)
                    |> Maybe.withDefault (Html.text "")

            NoDialog ->
                Html.text ""
        , model.notice
            |> Maybe.map noticeView
            |> Maybe.withDefault (Html.text "")
        ]
    }


sortListings : Marketplace.SortOrder -> List Listing -> List Listing
sortListings sortOrder listings =
    case sortOrder of
        Marketplace.Recommended ->
            listings

        Marketplace.PriceAscending ->
            Marketplace.sortByPrice listings


hero : Model -> Html.Html (PagesMsg Msg)
hero model =
    Html.section [ Attr.class "hero" ]
        [ Html.div [ Attr.class "hero-copy" ]
            [ Html.p [ Attr.class "eyebrow" ] [ Html.text "A happier kind of neighborhood" ]
            , Html.h1 [] [ Html.text "Good things,\nshared nearby." ]
            , Html.p [ Attr.class "hero-description" ]
                [ Html.text "The things we need don't have to be things we own. Find what you need from people just around the corner." ]
            , Html.div [ Attr.class "hero-actions" ]
                [ Html.button
                    [ Attr.class "button button-primary"
                    , Events.onClick (PagesMsg.fromMsg ShowCreateForm)
                    ]
                    [ Html.text "Share something" ]
                , Html.a [ Attr.href "#discover", Attr.class "text-link" ] [ Html.text "Explore the neighborhood ↓" ]
                ]
            , Html.div [ Attr.class "hero-proof" ]
                [ Html.div [ Attr.class "avatar-stack", Attr.attribute "aria-hidden" "true" ]
                    [ Html.span [ Attr.class "avatar avatar-one" ] [ Html.text "M" ]
                    , Html.span [ Attr.class "avatar avatar-two" ] [ Html.text "J" ]
                    , Html.span [ Attr.class "avatar avatar-three" ] [ Html.text "P" ]
                    ]
                , Html.p [] [ Html.strong [] [ Html.text "Neighbors helping neighbors" ], Html.br [] [], Html.text "One useful thing at a time" ]
                ]
            ]
        , Html.div [ Attr.class "hero-art", Attr.attribute "aria-hidden" "true" ]
            [ Html.div [ Attr.class "sun-shape" ] []
            , Html.div [ Attr.class "hero-card hero-card-main" ]
                [ Html.div [ Attr.class "hero-card-art art-sand" ] [ Html.text "🛠️" ]
                , Html.p [] [ Html.text "Cordless drill set" ]
                , Html.span [] [ Html.text "Shared with care" ]
                ]
            , Html.div [ Attr.class "hero-card hero-card-note" ]
                [ Html.span [] [ Html.text "✳" ]
                , Html.p [] [ Html.text "Borrow local.\nFeel good." ]
                ]
            , Html.div [ Attr.class "hero-sticker" ] [ Html.text "Good\nneighbors\nmake it." ]
            ]
        ]


browseSection : Model -> List Listing -> Int -> Int -> Html.Html (PagesMsg Msg)
browseSection model listings resultCount pageTotal =
    Html.section [ Attr.id "discover", Attr.class "browse-section" ]
        [ Html.div [ Attr.class "section-heading" ]
            [ Html.div []
                [ Html.p [ Attr.class "eyebrow" ] [ Html.text "The neighborhood shelf" ]
                , Html.h2 [] [ Html.text "Find your next favorite." ]
                , Html.p [ Attr.class "section-subtitle" ] [ Html.text "Useful things, shared by people nearby." ]
                ]
            , Html.label [ Attr.class "neighborhood-filter" ]
                [ Html.span [] [ Html.text "Around" ]
                , Html.select
                    [ Attr.value (Maybe.map Marketplace.neighborhoodName model.neighborhood |> Maybe.withDefault "")
                    , Events.onInput (NeighborhoodSelected >> PagesMsg.fromMsg)
                    , Attr.attribute "aria-label" "Filter by neighborhood"
                    ]
                    (Html.option [ Attr.value "" ] [ Html.text "All neighborhoods" ]
                        :: List.map
                            (\neighborhood ->
                                Html.option
                                    [ Attr.value (Marketplace.neighborhoodName neighborhood) ]
                                    [ Html.text (Marketplace.neighborhoodName neighborhood) ]
                            )
                            Marketplace.neighborhoods
                    )
                ]
            ]
        , Html.div [ Attr.class "browse-toolbar" ]
            [ Html.div [ Attr.class "search-box" ]
                [ Html.span [ Attr.attribute "aria-hidden" "true" ] [ Html.text "⌕" ]
                , Html.input
                    [ Attr.type_ "search"
                    , Attr.placeholder "Search for a drill, tent, mixer..."
                    , Attr.value model.query
                    , Events.onInput (SearchChanged >> PagesMsg.fromMsg)
                    , Attr.attribute "aria-label" "Search items and neighbors"
                    ]
                    []
                , if model.query /= "" then
                    Html.button
                        [ Attr.class "clear-search"
                        , Attr.attribute "aria-label" "Clear search"
                        , Events.onClick (PagesMsg.fromMsg (SearchChanged ""))
                        ]
                        [ Html.text "×" ]

                  else
                    Html.text ""
                ]
            , Html.button
                [ Attr.class "sort-button"
                , Events.onClick (PagesMsg.fromMsg SortByPrice)
                , Attr.attribute "aria-pressed"
                    (case model.sortOrder of
                        Marketplace.Recommended ->
                            "false"

                        Marketplace.PriceAscending ->
                            "true"
                    )
                ]
                [ Html.span [ Attr.attribute "aria-hidden" "true" ] [ Html.text "↕" ]
                , Html.text
                    (case model.sortOrder of
                        Marketplace.Recommended ->
                            "Sort: recommended"

                        Marketplace.PriceAscending ->
                            "Price: low to high"
                    )
                ]
            ]
        , Html.div [ Attr.class "category-list", Attr.attribute "role" "group", Attr.attribute "aria-label" "Filter by category" ]
            (List.map (categoryButton model.category) (Nothing :: List.map Just Marketplace.categories))
        , Html.div [ Attr.class "results-bar" ]
            [ Html.p []
                [ Html.strong [] [ Html.text (String.fromInt resultCount) ]
                , Html.text
                    (if resultCount == 1 then
                        " good thing nearby"

                     else
                        " good things nearby"
                    )
                ]
            , Html.button
                [ Attr.class "share-inline"
                , Events.onClick (PagesMsg.fromMsg ShowCreateForm)
                ]
                [ Html.text "+ Share an item" ]
            ]
        , if List.isEmpty listings then
            Html.div [ Attr.class "empty-state" ]
                [ Html.span [ Attr.attribute "aria-hidden" "true" ] [ Html.text "⌕" ]
                , Html.h3 [] [ Html.text "Nothing on this shelf just yet." ]
                , Html.p [] [ Html.text "Try another search or clear a filter to see more neighborly finds." ]
                , Html.button
                    [ Attr.class "button button-secondary"
                    , Events.onClick (PagesMsg.fromMsg (SearchChanged ""))
                    ]
                    [ Html.text "Clear search" ]
                ]

          else
            Html.div [ Attr.class "listing-grid" ] (List.map listingCard listings)
        , if pageTotal > 1 then
            pagination model.page pageTotal

          else
            Html.text ""
        ]


categoryButton : Maybe Marketplace.Category -> Maybe Marketplace.Category -> Html.Html (PagesMsg Msg)
categoryButton activeCategory category =
    let
        label =
            category
                |> Maybe.map Marketplace.categoryName
                |> Maybe.withDefault "Everything"

        isActive =
            activeCategory == category
    in
    Html.button
        [ Attr.class
            (if isActive then
                "category-chip is-active"

             else
                "category-chip"
            )
        , Events.onClick (PagesMsg.fromMsg (CategorySelected category))
        , Attr.attribute "aria-pressed"
            (if isActive then
                "true"

             else
                "false"
            )
        ]
        [ Html.text label ]


listingCard : Listing -> Html.Html (PagesMsg Msg)
listingCard listing =
    Html.article [ Attr.class "listing-card" ]
        [ Html.button
            [ Attr.class ("listing-art " ++ Marketplace.listingArtClass listing)
            , Events.onClick (PagesMsg.fromMsg (OpenListing (Marketplace.listingId listing)))
            , Attr.attribute "aria-label" ("View " ++ Marketplace.listingTitle listing)
            ]
            [ Html.span [ Attr.class "listing-emoji", Attr.attribute "aria-hidden" "true" ] [ Html.text (Marketplace.listingEmoji listing) ]
            , Html.span [ Attr.class "listing-category" ] [ Html.text (Marketplace.categoryName (Marketplace.listingCategory listing)) ]
            ]
        , Html.div [ Attr.class "listing-info" ]
            [ Html.div [ Attr.class "listing-title-row" ]
                [ Html.h3 [] [ Html.text (Marketplace.listingTitle listing) ]
                , Html.span [ Attr.class "listing-price" ] [ Html.text (Marketplace.priceLabel (Marketplace.listingPrice listing)) ]
                ]
            , Html.p [ Attr.class "listing-location" ]
                [ Html.span [ Attr.attribute "aria-hidden" "true" ] [ Html.text "⌖" ]
                , Html.text (Marketplace.neighborhoodName (Marketplace.listingNeighborhood listing) ++ " · shared by " ++ Marketplace.listingOwner listing)
                ]
            , Html.button
                [ Attr.class "card-link"
                , Events.onClick (PagesMsg.fromMsg (OpenListing (Marketplace.listingId listing)))
                ]
                [ Html.text "Take a closer look ↗" ]
            ]
        ]


pagination : Int -> Int -> Html.Html (PagesMsg Msg)
pagination current total =
    Html.nav [ Attr.class "pagination", Attr.attribute "aria-label" "Listing pages" ]
        [ Html.button
            [ Attr.class "page-button"
            , Attr.disabled (current <= 1)
            , Events.onClick (PagesMsg.fromMsg (PageSelected (current - 1)))
            ]
            [ Html.text "← Previous" ]
        , Html.span [] [ Html.text ("Page " ++ String.fromInt current ++ " of " ++ String.fromInt total) ]
        , Html.button
            [ Attr.class "page-button"
            , Attr.disabled (current >= total)
            , Events.onClick (PagesMsg.fromMsg (PageSelected (current + 1)))
            ]
            [ Html.text "Next →" ]
        ]


createDialog : Model -> Html.Html (PagesMsg Msg)
createDialog model =
    Html.div [ Attr.class "dialog-backdrop", Attr.attribute "role" "presentation" ]
        [ Html.section [ Attr.class "dialog", Attr.attribute "role" "dialog", Attr.attribute "aria-modal" "true", Attr.attribute "aria-labelledby" "create-title" ]
            [ Html.div [ Attr.class "dialog-heading" ]
                [ Html.div []
                    [ Html.p [ Attr.class "eyebrow" ] [ Html.text "Pass the good along" ]
                    , Html.h2 [ Attr.id "create-title" ] [ Html.text "Share something useful." ]
                    ]
                , closeButton HideCreateForm
                ]
            , Html.p [ Attr.class "dialog-intro" ] [ Html.text "Your listing is saved on the server and stays up for 7 days. Add a contact method that neighbors can use directly." ]
            , Html.p [ Attr.class "contact-privacy-note" ] [ Html.text "Contact details are visible to everyone who can view the listing. Only share information you are comfortable making public." ]
            , Html.label [ Attr.class "field-label" ]
                [ Html.text "Item name"
                , Html.input
                    [ Attr.value model.draft.title
                    , Attr.placeholder "e.g. Cordless drill set"
                    , Attr.maxlength 120
                    , Events.onInput (TitleChanged >> PagesMsg.fromMsg)
                    ]
                    []
                ]
            , Html.div [ Attr.class "field-row" ]
                [ Html.label [ Attr.class "field-label" ]
                    [ Html.text "Category"
                    , Html.select
                        [ Attr.value (Marketplace.categoryName model.draft.category)
                        , Events.onInput (CategoryDraftChanged >> PagesMsg.fromMsg)
                        ]
                        (List.map
                            (\category ->
                                Html.option
                                    [ Attr.value (Marketplace.categoryName category) ]
                                    [ Html.text (Marketplace.categoryName category) ]
                            )
                            Marketplace.categories
                        )
                    ]
                , Html.label [ Attr.class "field-label" ]
                    [ Html.text "Neighborhood"
                    , Html.select
                        [ Attr.value (Marketplace.neighborhoodName model.draft.neighborhood)
                        , Events.onInput (NeighborhoodDraftChanged >> PagesMsg.fromMsg)
                        ]
                        (List.map
                            (\neighborhood ->
                                Html.option
                                    [ Attr.value (Marketplace.neighborhoodName neighborhood) ]
                                    [ Html.text (Marketplace.neighborhoodName neighborhood) ]
                            )
                            Marketplace.neighborhoods
                        )
                    ]
                ]
            , Html.label [ Attr.class "field-label" ]
                [ Html.text "Daily price (use 0 for free)"
                , Html.div [ Attr.class "price-input" ]
                    [ Html.span [] [ Html.text "$" ]
                    , Html.input
                        [ Attr.type_ "number"
                        , Attr.min "0"
                        , Attr.step "0.01"
                        , Attr.value model.draft.price
                        , Events.onInput (PriceChanged >> PagesMsg.fromMsg)
                        ]
                        []
                    , Html.span [] [ Html.text "per day" ]
                    ]
                ]
            , Html.label [ Attr.class "field-label" ]
                [ Html.text "How can neighbors contact you?"
                , Html.textarea
                    [ Attr.value model.draft.contact
                    , Attr.placeholder "Phone, email, Telegram, WhatsApp, or any other contact details"
                    , Attr.rows 2
                    , Attr.maxlength 500
                    , Events.onInput (ContactChanged >> PagesMsg.fromMsg)
                    ]
                    []
                ]
            , Html.label [ Attr.class "field-label" ]
                [ Html.text "A few details (optional)"
                , Html.textarea
                    [ Attr.value model.draft.description
                    , Attr.placeholder "What should a neighbor know before borrowing it?"
                    , Attr.rows 3
                    , Attr.maxlength 2000
                    , Events.onInput (DescriptionChanged >> PagesMsg.fromMsg)
                    ]
                    []
                ]
            , Html.div [ Attr.class "dialog-actions" ]
                [ Html.button
                    [ Attr.class "button button-secondary"
                    , Attr.disabled (model.submission == Submitting)
                    , Events.onClick (PagesMsg.fromMsg HideCreateForm)
                    ]
                    [ Html.text "Maybe later" ]
                , Html.button
                    [ Attr.class "button button-primary"
                    , Attr.disabled (model.submission == Submitting)
                    , Events.onClick (PagesMsg.fromMsg CreateListing)
                    ]
                    [ Html.text
                        (case model.submission of
                            ReadyToSubmit ->
                                "Add to the shelf"

                            Submitting ->
                                "Saving..."
                        )
                    ]
                ]
            ]
        ]


listingDialog : Int -> Marketplace.PublishedListing -> Html.Html (PagesMsg Msg)
listingDialog now published =
    let
        listing =
            Marketplace.publishedListing published

        daysRemaining =
            max 1 ((Marketplace.listingExpiresAt published - now + 86400000 - 1) // 86400000)
    in
    Html.div [ Attr.class "dialog-backdrop", Attr.attribute "role" "presentation" ]
        [ Html.section [ Attr.class "dialog detail-dialog", Attr.attribute "role" "dialog", Attr.attribute "aria-modal" "true", Attr.attribute "aria-labelledby" "detail-title" ]
            [ Html.div [ Attr.class ("detail-art " ++ Marketplace.listingArtClass listing) ]
                [ Html.span [ Attr.attribute "aria-hidden" "true" ] [ Html.text (Marketplace.listingEmoji listing) ]
                , closeButton CloseListing
                ]
            , Html.p [ Attr.class "eyebrow" ] [ Html.text (Marketplace.categoryName (Marketplace.listingCategory listing)) ]
            , Html.h2 [ Attr.id "detail-title" ] [ Html.text (Marketplace.listingTitle listing) ]
            , Html.p [ Attr.class "listing-location" ] [ Html.text (Marketplace.neighborhoodName (Marketplace.listingNeighborhood listing) ++ " · shared by " ++ Marketplace.listingOwner listing) ]
            , Html.p [ Attr.class "detail-description" ] [ Html.text (Marketplace.listingDescription listing) ]
            , Html.div [ Attr.class "contact-details" ]
                [ Html.h3 [] [ Html.text "Contact the sharer directly" ]
                , Html.p [ Attr.class "contact-value" ] [ Html.text (Marketplace.contactText (Marketplace.listingContact listing)) ]
                ]
            , Html.div [ Attr.class "detail-footer" ]
                [ Html.span [ Attr.class "detail-price" ] [ Html.text (Marketplace.priceLabel (Marketplace.listingPrice listing)) ]
                , Html.span [ Attr.class "expiry-note" ]
                    [ Html.text
                        ("Expires in "
                            ++ String.fromInt daysRemaining
                            ++ (if daysRemaining == 1 then
                                    " day"

                                else
                                    " days"
                               )
                        )
                    ]
                ]
            ]
        ]


closeButton : Msg -> Html.Html (PagesMsg Msg)
closeButton msg =
    Html.button
        [ Attr.class "close-button"
        , Attr.attribute "aria-label" "Close dialog"
        , Events.onClick (PagesMsg.fromMsg msg)
        ]
        [ Html.text "×" ]


noticeView : String -> Html.Html (PagesMsg Msg)
noticeView message =
    Html.div [ Attr.class "notice", Attr.attribute "role" "status" ]
        [ Html.p [] [ Html.text message ]
        , Html.button
            [ Attr.class "notice-close"
            , Attr.attribute "aria-label" "Dismiss message"
            , Events.onClick (PagesMsg.fromMsg DismissNotice)
            ]
            [ Html.text "×" ]
        ]
