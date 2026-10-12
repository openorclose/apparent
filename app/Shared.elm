module Shared exposing (Data, Model, Msg(..), SharedMsg(..), template)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Html
import Html.Attributes as Attr
import Pages.Flags
import Pages.PageUrl exposing (PageUrl)
import Route exposing (Route)
import SharedTemplate exposing (SharedTemplate)
import UrlPath exposing (UrlPath)
import View exposing (View)


template : SharedTemplate Msg Model Data msg
template =
    { init = init
    , update = update
    , view = view
    , data = data
    , subscriptions = subscriptions
    , onPageChange = Nothing
    }


type Msg
    = SharedMsg SharedMsg


type SharedMsg
    = NoOp


type alias Data =
    ()


type alias Model =
    {}


init :
    Pages.Flags.Flags
    ->
        Maybe
            { path :
                { path : UrlPath
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : Maybe Route
            , pageUrl : Maybe PageUrl
            }
    -> ( Model, Effect Msg )
init flags maybePagePath =
    ( {}, Effect.none )


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        SharedMsg NoOp ->
            ( model, Effect.none )


subscriptions : UrlPath -> Model -> Sub Msg
subscriptions _ _ =
    Sub.none


data : BackendTask FatalError Data
data =
    BackendTask.succeed ()


view :
    Data
    ->
        { path : UrlPath
        , route : Maybe Route
        }
    -> Model
    -> (Msg -> msg)
    -> View msg
    -> { body : List (Html.Html msg), title : String }
view sharedData page model toMsg pageView =
    { body =
        [ Html.header [ Attr.class "site-header" ]
            [ Html.a [ Attr.href "/", Attr.class "brand", Attr.attribute "aria-label" "AppaRent home" ]
                [ Html.span [ Attr.class "brand-mark", Attr.attribute "aria-hidden" "true" ] [ Html.text "a" ]
                , Html.text "AppaRent"
                ]
            , Html.nav [ Attr.class "site-nav", Attr.attribute "aria-label" "Main navigation" ]
                [ Html.a [ Attr.href "/#discover" ] [ Html.text "Explore" ]
                , Html.a [ Attr.href "/#about" ] [ Html.text "How it works" ]
                ]
            , Html.a [ Attr.href "/#discover", Attr.class "header-link" ] [ Html.text "Find something nearby ↗" ]
            ]
        , Html.main_ [] pageView.body
        , Html.footer [ Attr.class "site-footer", Attr.id "about" ]
            [ Html.a [ Attr.href "/", Attr.class "brand footer-brand" ]
                [ Html.span [ Attr.class "brand-mark", Attr.attribute "aria-hidden" "true" ] [ Html.text "a" ]
                , Html.text "AppaRent"
                ]
            , Html.p [] [ Html.text "Borrow a little. Share a lot. Make your block feel like home." ]
            , Html.span [] [ Html.text "Made for good neighbors." ]
            ]
        ]
    , title = pageView.title
    }
