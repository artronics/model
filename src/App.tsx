import {useEffect} from 'react'
import './App.css'
import {invoke} from '@tauri-apps/api';
import SearchPopup from "./components/SearchPopup.tsx";

function App() {
    useEffect(() => {
        invoke('greet', {name: 'World'})
            // `invoke` returns a Promise
            .then((response) => console.log(response))
    }, []);

    return (
        <div className="w-screen h-screen">
            <SearchPopup/>

        </div>

    )
}

export default App
