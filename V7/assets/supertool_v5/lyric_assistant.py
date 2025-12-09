import sys
import requests
import json
import os
import argparse

def get_datamuse(endpoint, params):
    url = f"https://api.datamuse.com/{endpoint}"
    try:
        response = requests.get(url, params=params)
        if response.status_code == 200:
            return response.json()
    except Exception as e:
        print(f"Error connecting to Datamuse API: {e}")
    return []

def find_rhymes(word):
    print(f"\n--- Rhymes for '{word}' ---")
    results = get_datamuse("words", {"rel_rhy": word, "max": 20})
    if results:
        words = [r['word'] for r in results]
        # Print in columns
        for i in range(0, len(words), 4):
            print("\t".join(f"{w:<15}" for w in words[i:i+4]))
    else:
        print("No rhymes found.")

def find_related(word):
    print(f"\n--- Words related to '{word}' ---")
    results = get_datamuse("words", {"ml": word, "max": 20})
    if results:
        words = [r['word'] for r in results]
        for i in range(0, len(words), 4):
            print("\t".join(f"{w:<15}" for w in words[i:i+4]))
    else:
        print("No related words found.")

def generate_lyrics_ollama(prompt, model="llama3", style="Verse-Chorus"):
    """Generate lyrics using a local Ollama instance (Free, Offline)"""
    print(f"\n--- Generating Lyrics (Local Ollama: {model}) for: '{prompt}' ---")
    print("Thinking... (this depends on your GPU/CPU)")

    url = "http://localhost:11434/api/generate"
    
    system_prompt = "You are a professional songwriter. Write creative, rhythmic lyrics."
    if style:
        system_prompt += f" Structure the song as {style}."
    
    payload = {
        "model": model,
        "prompt": f"{system_prompt}\n\nWrite a song about: {prompt}",
        "stream": False
    }

    try:
        response = requests.post(url, json=payload)
        if response.status_code == 200:
            result = response.json()
            content = result.get('response', '')
            print("\n" + "="*40)
            print(content)
            print("="*40 + "\n")
            
            save = input("Save these lyrics to file? (y/n): ").lower()
            if save == 'y':
                filename = input("Enter filename (e.g., song.txt): ")
                with open(filename, 'w') as f:
                    f.write(content)
                print(f"Saved to {filename}")
        else:
            print(f"Error from Ollama: {response.status_code}")
            print("Make sure Ollama is running (run 'ollama serve' in a terminal).")
    except requests.exceptions.ConnectionError:
        print("\n[!] Could not connect to Ollama.")
        print("    1. Install Ollama from https://ollama.com")
        print("    2. Run 'ollama run llama3' (or mistral) in a terminal to download a model.")
        print("    3. Keep 'ollama serve' running in the background.")
    except Exception as e:
        print(f"Error: {e}")

def generate_lyrics_ai(prompt, api_key, style="Verse-Chorus"):
    if not api_key:
        print("\n[!] OpenAI API Key is required for AI generation.")
        print("    You can get one at https://platform.openai.com/")
        return

    print(f"\n--- Generating Lyrics for: '{prompt}' ---")
    print("Contacting AI... (this may take a few seconds)")
    
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }
    
    system_prompt = "You are a professional songwriter. Write creative, rhythmic lyrics."
    if style:
        system_prompt += f" Structure the song as {style}."

    data = {
        "model": "gpt-3.5-turbo",
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": f"Write a song about: {prompt}"}
        ],
        "temperature": 0.7
    }
    
    try:
        response = requests.post("https://api.openai.com/v1/chat/completions", headers=headers, json=data)
        if response.status_code == 200:
            result = response.json()
            content = result['choices'][0]['message']['content']
            print("\n" + "="*40)
            print(content)
            print("="*40 + "\n")
            
            # Offer to save
            save = input("Save these lyrics to file? (y/n): ").lower()
            if save == 'y':
                filename = input("Enter filename (e.g., song.txt): ")
                with open(filename, 'w') as f:
                    f.write(content)
                print(f"Saved to {filename}")
        else:
            print(f"Error from AI API: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"Error: {e}")

def main():
    parser = argparse.ArgumentParser(description="Songwriting Assistant")
    parser.add_argument("--mode", choices=["rhyme", "related", "generate", "interactive"], default="interactive")
    parser.add_argument("--word", help="Word to find rhymes/related for")
    parser.add_argument("--prompt", help="Prompt for lyric generation")
    parser.add_argument("--key", help="OpenAI API Key", default=os.environ.get("OPENAI_API_KEY"))
    
    args = parser.parse_args()

    if args.mode == "rhyme" and args.word:
        find_rhymes(args.word)
    elif args.mode == "related" and args.word:
        find_related(args.word)
    elif args.mode == "generate" and args.prompt:
        generate_lyrics_ai(args.prompt, args.key)
    else:
        # Interactive Loop
        print("\n🎵 Welcome to the Songwriting Assistant 🎵")
        while True:
            print("\n1. Find Rhymes")
            print("2. Find Related Words / Synonyms")
            print("3. Generate Lyrics (OpenAI - Paid/Key Required)")
            print("4. Generate Lyrics (Ollama - Free/Local)")
            print("5. Exit")
            choice = input("Select option (1-5): ")
            
            if choice == "1":
                w = input("Enter word to rhyme: ")
                find_rhymes(w)
            elif choice == "2":
                w = input("Enter word for meaning/synonyms: ")
                find_related(w)
            elif choice == "3":
                p = input("Enter song topic/mood: ")
                k = args.key
                if not k:
                    print("An OpenAI API Key is required.")
                    k = input("Enter OpenAI API Key (leave blank to cancel): ").strip()
                if k:
                    generate_lyrics_ai(p, k)
            elif choice == "4":
                p = input("Enter song topic/mood: ")
                m = input("Enter model name (default: llama3): ").strip()
                if not m: m = "llama3"
                generate_lyrics_ollama(p, model=m)
            elif choice == "5":
                print("Keep writing! 🎵")
                break

if __name__ == "__main__":
    main()
