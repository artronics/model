import {useEffect} from 'react'
import './App.css'
import {invoke} from '@tauri-apps/api';
import SearchPopup from "./components/SearchPopup.tsx";
import Editor from "./components/Editor.tsx";
import {RecoilRoot} from "recoil";

function App() {
    useEffect(() => {
        invoke('greet', {name: 'World'})
            // `invoke` returns a Promise
            .then((response) => console.log(response))
    }, []);

    return (
        <RecoilRoot>
            <div className="w-screen h-screen">
                <SearchPopup/>
                <Editor/>
            </div>
        </RecoilRoot>

    )
}

export default App
