module Route exposing
    ( HistoryParams
    , MapsParams
    , OverlayParams
    , Route(..)
    , TimerParams
    , dateToString
    , historyParams0
    , href
    , mapsParams0
    , overlayParams0
    , parse
    , stringify
    , timerParams0
    )

import Html as H
import Html.Attributes as A
import Http
import ISO8601
import Maybe.Extra
import Regex
import Time
import Url exposing (Url)
import Url.Parser as P exposing ((</>), (<?>))
import Url.Parser.Query as Q


flags0 =
    { goals = True }


type alias HistoryParams =
    { page : Int
    , search : Maybe String
    , sort : Maybe String
    , after : Maybe Time.Posix
    , before : Maybe Time.Posix
    , goal : Maybe String
    , enableGoals : Bool
    }


historyParams0 =
    HistoryParams 0 Nothing Nothing Nothing Nothing Nothing flags0.goals


type alias MapsParams =
    { search : Maybe String
    , after : Maybe Time.Posix
    , before : Maybe Time.Posix
    }


mapsParams0 =
    MapsParams Nothing Nothing Nothing


type alias TimerParams =
    { after : Maybe Time.Posix
    , goal : Maybe String
    , enableGoals : Bool
    }


timerParams0 =
    TimerParams Nothing Nothing flags0.goals


type alias OverlayParams =
    { after : Maybe Time.Posix
    , goal : Maybe String
    , enableGoals : Bool
    }


overlayParams0 =
    OverlayParams Nothing Nothing flags0.goals


type Route
    = History HistoryParams
    | Maps MapsParams
    | Timer TimerParams
    | Overlay OverlayParams
    | Changelog
    | Debug
    | DebugDumpLines
    | DebugMapIcons
    | NotFound Url


parse : Url -> Route
parse loc =
    loc
        |> hashUrl
        |> P.parse parser
        |> Maybe.withDefault (NotFound loc)
        |> Debug.log "navigate to"


hashUrl : Url -> Url
hashUrl url =
    -- elm 0.19 removed parseHash; booo. This function fakes it by transforming
    -- `https://example.com/?flag=1#/some/path?some=query` to
    -- `https://example.com/some/path?flag=1&some=query` for the parser.
    case url.fragment |> Maybe.withDefault "" |> String.split "?" of
        path :: queries ->
            let
                query =
                    queries |> String.join "?"

                urlQuery =
                    url.query |> Maybe.Extra.unwrap "" (\s -> s ++ "&")
            in
            { url | path = path, query = urlQuery ++ query |> Just }

        [] ->
            { url | path = "", query = url.query }


decodeString : P.Parser (String -> a) a
decodeString =
    P.map
        (\s ->
            s
                |> Url.percentDecode
                |> Maybe.withDefault s
        )
        P.string


dateFromString : String -> Maybe Time.Posix
dateFromString =
    ISO8601.fromString >> Result.toMaybe >> Maybe.map ISO8601.toPosix


dateToString : Time.Posix -> String
dateToString =
    -- compatible with dateFromString, identical to <input type="datetime-local">, and also reasonably short/user-readable
    ISO8601.fromPosix >> ISO8601.toString


dateParam : String -> Q.Parser (Maybe Time.Posix)
dateParam name =
    Q.custom name (List.head >> Maybe.andThen dateFromString)


boolParam : Bool -> String -> Q.Parser Bool
boolParam default name =
    let
        parse_ : String -> Bool
        parse_ s =
            not <| s == "" || s == "0" || s == "no" || s == "n" || s == "False" || s == "false"
    in
    Q.custom name (List.head >> Maybe.Extra.unwrap default parse_)


parser : P.Parser (Route -> a) a
parser =
    P.oneOf
        [ P.map Timer <|
            P.map TimerParams <|
                P.oneOf [ P.top, P.s "timer" ]
                    <?> dateParam "a"
                    <?> Q.string "g"
                    <?> boolParam flags0.goals "enableGoals"
        , P.map Overlay <|
            P.map OverlayParams <|
                P.oneOf [ P.top, P.s "overlay" ]
                    <?> dateParam "a"
                    <?> Q.string "g"
                    <?> boolParam flags0.goals "enableGoals"
        , P.map History <|
            P.map (\p -> HistoryParams (Maybe.withDefault 0 p)) <|
                P.s "history"
                    <?> Q.int "p"
                    <?> Q.string "q"
                    <?> Q.string "o"
                    <?> dateParam "a"
                    <?> dateParam "b"
                    <?> Q.string "g"
                    <?> boolParam flags0.goals "enableGoals"

        -- , P.map MapsRoot <| P.s "map"
        , P.map Maps <|
            P.map MapsParams <|
                P.s "map"
                    <?> Q.string "q"
                    <?> dateParam "a"
                    <?> dateParam "b"
        , P.map Changelog <| P.s "changelog"
        , P.map (always Changelog) <| P.s "changelog" </> P.string
        , P.map Debug <| P.s "debug"
        , P.map DebugDumpLines <| P.s "debug" </> P.s "dumplines"
        , P.map DebugMapIcons <| P.s "debug" </> P.s "mapicons"
        ]


encodeQS : List ( String, Maybe String ) -> String
encodeQS pairs0 =
    let
        pairs : List ( String, String )
        pairs =
            pairs0
                |> List.map (\( k, v ) -> Maybe.map (\vv -> ( k, vv )) v)
                |> Maybe.Extra.values
    in
    if List.isEmpty pairs then
        ""

    else
        pairs
            -- TODO should really rewrite to use elm-0.19's Url.Builder instead of Url.percentEncode;
            -- I'm just too lazy to redesign this while migrating everything else to 0.19
            |> List.map (\( k, v ) -> Url.percentEncode k ++ "=" ++ Url.percentEncode v)
            |> String.join "&"
            |> (++) "?"


stringify : Route -> String
stringify route =
    case route of
        History qs ->
            "#/history"
                ++ encodeQS
                    [ ( "p"
                      , if qs.page == 0 then
                            Nothing

                        else
                            qs.page |> String.fromInt |> Just
                      )
                    , ( "q", qs.search )
                    , ( "o", qs.sort )
                    , ( "a", Maybe.map dateToString qs.after )
                    , ( "b", Maybe.map dateToString qs.before )
                    , ( "g", qs.goal )
                    ]

        Maps qs ->
            "#/map"
                ++ encodeQS
                    [ ( "q", qs.search )
                    , ( "a", Maybe.map dateToString qs.after )
                    , ( "b", Maybe.map dateToString qs.before )
                    ]

        Timer qs ->
            "#/"
                ++ encodeQS
                    [ ( "a", Maybe.map dateToString qs.after )
                    , ( "g", qs.goal )
                    ]

        Overlay qs ->
            "#/overlay"
                ++ encodeQS
                    [ ( "a", Maybe.map dateToString qs.after )
                    , ( "g", qs.goal )
                    ]

        Changelog ->
            "#/changelog"

        Debug ->
            "#/debug"

        DebugDumpLines ->
            "#/debug/dumplines"

        DebugMapIcons ->
            "#/debug/mapicons"

        NotFound loc ->
            "#" ++ (loc.fragment |> Maybe.withDefault "")


href : Route -> H.Attribute msg
href =
    A.href << stringify
