import React, {useEffect, useRef} from "react";
import {atom, selector, useRecoilValue, useSetRecoilState} from "recoil";
import {emit, listen} from "@tauri-apps/api/event";

function TabBar() {
    const item = (t: string, i: number) => (<li key={i} className="inline-block p-2">{t}</li>)
    const items = ["Files", "Classes"]

    return (
        <ol className="border-b-[1px] border-gray-800 px-2 ">
            {items.map(item)}
        </ol>
    )
}

const textState = atom({
    key: 'search-popup-text',
    default: '',
});

function SearchInput() {
    const setText = useSetRecoilState(textState);
    const onChange = (event: React.FormEvent<HTMLInputElement>) => {
        setText(event.currentTarget.value);
    };

    return (
        <div className="flex flex-row p-2">
            <i className="fa fa-search px-2 mt-[2px]"></i>
            <input onChange={onChange} className="grow pl-2 bg-stone-600"/>
        </div>
    )
}

interface SearchResult {
    icon: string,
    text: string
}

function Results(props: { items: SearchResult[] }) {
    const item = (r: SearchResult, i: number) => (<li key={i}><i className={`fa fa-${r.icon} pr-2`}/>{r.text}</li>)
    return (
        <div className="px-4 max-h-80 overflow-y-auto">
            <ol>
                {props.items.map(item)}
            </ol>
        </div>
    )
}

function PopupFooter() {
    return (
        <div className="border-t-[1px] border-gray-800 px-4">information in the footer</div>
    )
}

const searchResults = selector({
    key: 'search-results',
    get: ({get}) => {
        const pattern = get(textState);
        console.log(pattern)
        return search(pattern)
    },
});


// emits the `click` event with the object payload
function SearchPopup() {
    const isLoaded = useRef(false);
    useEffect(() => {
        const unlisten = listen('click', (event) => {
            console.log("got event in front end", event)

        })

    }, []);
    useEffect(() => {
        if (!isLoaded.current) {
            emit('click', {
                message: 'from front end payload',
            })
            console.log("search pop up")
            isLoaded.current = true
        }
        return () => {
        }
    });
    const results = useRecoilValue(searchResults);
    return (
        <>
            <div className="bg-stone-600 w-full rounded-md">
                <TabBar/>
                <SearchInput/>
                <Results items={results}/>
                <PopupFooter/>
            </div>
        </>
    )
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
function search(_pattern: string): SearchResult[] {
    // create random entries for testing
    const num = Math.floor(Math.random() * 100)
    const chooseFile = () => {
        const files = [
            "./font-awesome/fonts/fontawesome-webfont.woff",
            "./font-awesome/fonts/fontawesome-webfont.eot",
            "./type-check",
            "./type-check/LICENSE",
            "./type-check/README.md",
            "./type-check/package.json",
            "./type-check/lib",
            "./type-check/lib/parse-type.js",
            "./type-check/lib/index.js",
            "./type-check/lib/check.js",
            "./locate-path",
            "./locate-path/license",
            "./locate-path/index.js",
            "./locate-path/readme.md",
            "./locate-path/package.json",
            "./locate-path/index.d.ts",
            "./.vite",
            "./.vite/deps",
            "./.vite/deps/_metadata.json",
            "./.vite/deps/chunk-BZN7XFWI.js",
            "./.vite/deps/react-dom_client.js",
            "./.vite/deps/react_jsx-dev-runtime.js",
            "./.vite/deps/r",
        ]
        const fi = Math.floor(Math.random() * files.length)
        const icons = ["camera", "file", "envelope", "user"]
        const ii = Math.floor(Math.random() * icons.length)

        return {text: files[fi], icon: icons[ii]}
    }
    const r: SearchResult[] = []
    for (let i = 0; i < num; i++) {
        r.push(chooseFile())
    }
    return r
}

export default SearchPopup